package main

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

type config struct {
	port                 string
	allowedOrigin        string
	uploadClientToken    string
	cloudflareAccountID  string
	cloudflareAPIToken   string
	cloudflareDeliveryID string
	directUploadExpiry   time.Duration
}

type server struct {
	cfg    config
	client *http.Client
}

type directUploadRequest struct {
	EOAAddress  string `json:"eoaAddress"`
	FileName    string `json:"fileName"`
	ContentType string `json:"contentType"`
}

type directUploadResponse struct {
	UploadURL   string `json:"uploadURL"`
	ImageID     string `json:"imageID"`
	DeliveryURL string `json:"deliveryURL"`
}

type cloudflareDirectUploadRequest struct {
	RequireSignedURLs bool              `json:"requireSignedURLs"`
	Expiry            string            `json:"expiry"`
	Metadata          map[string]string `json:"metadata"`
}

type cloudflareDirectUploadResult struct {
	ID        string `json:"id"`
	UploadURL string `json:"uploadURL"`
}

type cloudflareError struct {
	Message string `json:"message"`
}

type cloudflareDirectUploadEnvelope struct {
	Success bool                         `json:"success"`
	Errors  []cloudflareError            `json:"errors"`
	Result  cloudflareDirectUploadResult `json:"result"`
}

var (
	errUnauthorized = errors.New("unauthorized")
	errBadRequest   = errors.New("bad request")
	errUpstream     = errors.New("upstream error")
	eoaPattern      = regexp.MustCompile(`^0x[a-fA-F0-9]{40}$`)
)

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("invalid config: %v", err)
	}

	s := &server{
		cfg: cfg,
		client: &http.Client{
			Timeout: 15 * time.Second,
		},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/v1/images/direct-upload", s.handleDirectUpload)

	h := s.withCORS(s.withRequestLogging(mux))

	httpServer := &http.Server{
		Addr:              ":" + cfg.port,
		Handler:           h,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("cloudflare image upload worker listening on :%s", cfg.port)
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}
}

func loadConfig() (config, error) {
	port := envOrDefault("PORT", "8080")
	allowedOrigin := envOrDefault("ALLOWED_ORIGIN", "*")
	uploadClientToken := strings.TrimSpace(os.Getenv("UPLOAD_CLIENT_TOKEN"))
	cloudflareAccountID := strings.TrimSpace(os.Getenv("CLOUDFLARE_ACCOUNT_ID"))
	cloudflareAPIToken := strings.TrimSpace(os.Getenv("CLOUDFLARE_IMAGES_API_TOKEN"))
	cloudflareDeliveryID := strings.TrimSpace(os.Getenv("CLOUDFLARE_IMAGES_DELIVERY_HASH"))

	if uploadClientToken == "" || cloudflareAccountID == "" || cloudflareAPIToken == "" || cloudflareDeliveryID == "" {
		return config{}, fmt.Errorf("UPLOAD_CLIENT_TOKEN, CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_IMAGES_API_TOKEN, and CLOUDFLARE_IMAGES_DELIVERY_HASH are required")
	}

	expirySeconds := parseBoundedInt(envOrDefault("DIRECT_UPLOAD_EXPIRY_SECONDS", "600"), 60, 3600, 600)

	return config{
		port:                 port,
		allowedOrigin:        allowedOrigin,
		uploadClientToken:    uploadClientToken,
		cloudflareAccountID:  cloudflareAccountID,
		cloudflareAPIToken:   cloudflareAPIToken,
		cloudflareDeliveryID: cloudflareDeliveryID,
		directUploadExpiry:   time.Duration(expirySeconds) * time.Second,
	}, nil
}

func (s *server) withRequestLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s (%s)", r.Method, r.URL.Path, time.Since(start).Round(time.Millisecond))
	})
}

func (s *server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", s.cfg.allowedOrigin)
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "authorization,content-type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func (s *server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "Method not allowed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *server) handleDirectUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "Method not allowed"})
		return
	}

	if err := s.authorize(r); err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Unauthorized"})
		return
	}

	var req directUploadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid JSON body."})
		return
	}

	if err := validateDirectUploadRequest(req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}

	resp, err := s.createDirectUpload(r.Context(), req)
	if err != nil {
		if errors.Is(err, errBadRequest) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid direct upload request."})
			return
		}
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

func (s *server) authorize(r *http.Request) error {
	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(header, "Bearer ") {
		return errUnauthorized
	}
	token := strings.TrimPrefix(header, "Bearer ")
	if subtle.ConstantTimeCompare([]byte(token), []byte(s.cfg.uploadClientToken)) != 1 {
		return errUnauthorized
	}
	return nil
}

func (s *server) createDirectUpload(ctx context.Context, req directUploadRequest) (directUploadResponse, error) {
	safeFileName := sanitizeFileName(req.FileName)
	if safeFileName == "" {
		return directUploadResponse{}, errBadRequest
	}

	expiresAt := time.Now().UTC().Add(s.cfg.directUploadExpiry).Format(time.RFC3339)
	cfPayload := cloudflareDirectUploadRequest{
		RequireSignedURLs: false,
		Expiry:            expiresAt,
		Metadata: map[string]string{
			"eoaAddress": strings.ToLower(req.EOAAddress),
			"fileName":   safeFileName,
			"source":     "metu-ios",
			"uploadedAt": time.Now().UTC().Format(time.RFC3339),
		},
	}

	body, err := json.Marshal(cfPayload)
	if err != nil {
		return directUploadResponse{}, err
	}

	url := fmt.Sprintf("https://api.cloudflare.com/client/v4/accounts/%s/images/v2/direct_upload", s.cfg.cloudflareAccountID)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return directUploadResponse{}, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+s.cfg.cloudflareAPIToken)
	httpReq.Header.Set("Content-Type", "application/json")

	httpResp, err := s.client.Do(httpReq)
	if err != nil {
		return directUploadResponse{}, err
	}
	defer httpResp.Body.Close()

	var envelope cloudflareDirectUploadEnvelope
	if err := json.NewDecoder(httpResp.Body).Decode(&envelope); err != nil {
		return directUploadResponse{}, fmt.Errorf("cloudflare returned malformed JSON: %w", err)
	}

	if httpResp.StatusCode < 200 || httpResp.StatusCode > 299 || !envelope.Success || envelope.Result.UploadURL == "" || envelope.Result.ID == "" {
		reason := "Failed to create direct upload URL."
		if len(envelope.Errors) > 0 && strings.TrimSpace(envelope.Errors[0].Message) != "" {
			reason = envelope.Errors[0].Message
		}
		return directUploadResponse{}, fmt.Errorf("%w: %s", errUpstream, reason)
	}

	deliveryURL := fmt.Sprintf("https://imagedelivery.net/%s/%s/public", s.cfg.cloudflareDeliveryID, envelope.Result.ID)
	return directUploadResponse{
		UploadURL:   envelope.Result.UploadURL,
		ImageID:     envelope.Result.ID,
		DeliveryURL: deliveryURL,
	}, nil
}

func validateDirectUploadRequest(req directUploadRequest) error {
	if !eoaPattern.MatchString(req.EOAAddress) {
		return errors.New("Invalid EOA address.")
	}

	fileName := strings.TrimSpace(req.FileName)
	if len(fileName) < 3 {
		return errors.New("Invalid file name.")
	}

	contentType := strings.ToLower(strings.TrimSpace(req.ContentType))
	if !strings.HasPrefix(contentType, "image/") {
		return errors.New("Only image content types are supported.")
	}

	switch contentType {
	case "image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic", "image/heif":
		return nil
	default:
		return errors.New("Unsupported image content type.")
	}
}

func sanitizeFileName(name string) string {
	name = strings.ToLower(strings.TrimSpace(name))
	if name == "" {
		return ""
	}

	var b strings.Builder
	for _, r := range name {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '.' || r == '_' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('-')
		}
	}

	cleaned := strings.Trim(strings.ReplaceAll(b.String(), "--", "-"), "-")
	if len(cleaned) > 140 {
		cleaned = cleaned[:140]
	}
	return cleaned
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed writing JSON response: %v", err)
	}
}

func envOrDefault(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func parseBoundedInt(raw string, min int, max int, fallback int) int {
	parsed, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil {
		return fallback
	}
	if parsed < min || parsed > max {
		return fallback
	}
	return parsed
}
