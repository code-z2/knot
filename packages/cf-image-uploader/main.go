package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

type config struct {
	port               string
	allowedOrigin      string
	uploadClientToken  string
	r2AccountID        string
	r2BucketName       string
	r2AccessKeyID      string
	r2SecretAccessKey  string
	r2PublicBaseURL    string
	r2Endpoint         string
	r2SigningRegion    string
	directUploadExpiry time.Duration
}

type server struct {
	cfg config
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

var (
	errUnauthorized = errors.New("unauthorized")
	errBadRequest   = errors.New("bad request")
	eoaPattern      = regexp.MustCompile(`^0x[a-fA-F0-9]{40}$`)
)

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("invalid config: %v", err)
	}

	s := &server{cfg: cfg}

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

	log.Printf("r2 image upload service listening on :%s", cfg.port)
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}
}

func loadConfig() (config, error) {
	port := envOrDefault("PORT", "8080")
	allowedOrigin := envOrDefault("ALLOWED_ORIGIN", "*")
	uploadClientToken := strings.TrimSpace(os.Getenv("UPLOAD_CLIENT_TOKEN"))
	r2AccountID := strings.TrimSpace(os.Getenv("R2_ACCOUNT_ID"))
	r2BucketName := strings.TrimSpace(os.Getenv("R2_BUCKET_NAME"))
	r2AccessKeyID := strings.TrimSpace(os.Getenv("R2_ACCESS_KEY_ID"))
	r2SecretAccessKey := strings.TrimSpace(os.Getenv("R2_SECRET_ACCESS_KEY"))
	r2PublicBaseURL := strings.TrimSpace(os.Getenv("R2_PUBLIC_BASE_URL"))

	if r2AccountID == "" {
		// Backward-compatible fallback.
		r2AccountID = strings.TrimSpace(os.Getenv("CLOUDFLARE_ACCOUNT_ID"))
	}

	if uploadClientToken == "" || r2AccountID == "" || r2BucketName == "" || r2AccessKeyID == "" || r2SecretAccessKey == "" || r2PublicBaseURL == "" {
		return config{}, fmt.Errorf("UPLOAD_CLIENT_TOKEN, R2_ACCOUNT_ID, R2_BUCKET_NAME, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, and R2_PUBLIC_BASE_URL are required")
	}

	expirySeconds := parseBoundedInt(envOrDefault("DIRECT_UPLOAD_EXPIRY_SECONDS", "600"), 60, 3600, 600)
	r2Endpoint := envOrDefault("R2_S3_ENDPOINT", fmt.Sprintf("https://%s.r2.cloudflarestorage.com", r2AccountID))
	r2SigningRegion := envOrDefault("R2_SIGNING_REGION", "auto")

	parsedEndpoint, err := url.Parse(r2Endpoint)
	if err != nil || parsedEndpoint.Scheme == "" || parsedEndpoint.Host == "" {
		return config{}, fmt.Errorf("invalid R2_S3_ENDPOINT: %q", r2Endpoint)
	}

	parsedPublicBase, err := url.Parse(r2PublicBaseURL)
	if err != nil || parsedPublicBase.Scheme == "" || parsedPublicBase.Host == "" {
		return config{}, fmt.Errorf("invalid R2_PUBLIC_BASE_URL: %q", r2PublicBaseURL)
	}

	return config{
		port:               port,
		allowedOrigin:      allowedOrigin,
		uploadClientToken:  uploadClientToken,
		r2AccountID:        r2AccountID,
		r2BucketName:       r2BucketName,
		r2AccessKeyID:      r2AccessKeyID,
		r2SecretAccessKey:  r2SecretAccessKey,
		r2PublicBaseURL:    strings.TrimRight(r2PublicBaseURL, "/"),
		r2Endpoint:         r2Endpoint,
		r2SigningRegion:    r2SigningRegion,
		directUploadExpiry: time.Duration(expirySeconds) * time.Second,
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

func (s *server) createDirectUpload(_ context.Context, req directUploadRequest) (directUploadResponse, error) {
	safeFileName := sanitizeFileName(req.FileName)
	if safeFileName == "" {
		return directUploadResponse{}, errBadRequest
	}

	contentType := strings.ToLower(strings.TrimSpace(req.ContentType))
	objectKey := buildObjectKey(strings.ToLower(req.EOAAddress), safeFileName)

	presignedURL, err := presignR2PutURL(
		s.cfg,
		objectKey,
		contentType,
		s.cfg.directUploadExpiry,
	)
	if err != nil {
		return directUploadResponse{}, fmt.Errorf("failed to create presigned upload URL: %w", err)
	}

	deliveryURL, err := buildPublicObjectURL(s.cfg.r2PublicBaseURL, objectKey)
	if err != nil {
		return directUploadResponse{}, fmt.Errorf("failed to build delivery URL: %w", err)
	}

	return directUploadResponse{
		UploadURL:   presignedURL,
		ImageID:     objectKey,
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

func buildObjectKey(eoaAddress, safeFileName string) string {
	timestamp := time.Now().UTC().Format("20060102-150405")
	randomSuffix := randomHex(6)
	return fmt.Sprintf("avatars/%s/%s-%s-%s", strings.TrimSpace(strings.ToLower(eoaAddress)), timestamp, randomSuffix, safeFileName)
}

func presignR2PutURL(cfg config, objectKey, contentType string, expires time.Duration) (string, error) {
	endpoint, err := url.Parse(cfg.r2Endpoint)
	if err != nil {
		return "", err
	}

	if endpoint.Scheme == "" || endpoint.Host == "" {
		return "", fmt.Errorf("invalid R2 endpoint")
	}

	now := time.Now().UTC()
	amzDate := now.Format("20060102T150405Z")
	shortDate := now.Format("20060102")
	expiresSeconds := int(expires.Seconds())
	if expiresSeconds < 1 {
		expiresSeconds = 600
	}

	credentialScope := fmt.Sprintf("%s/%s/s3/aws4_request", shortDate, cfg.r2SigningRegion)
	credentialValue := fmt.Sprintf("%s/%s", cfg.r2AccessKeyID, credentialScope)

	canonicalURI := "/" + encodePathSegment(cfg.r2BucketName) + "/" + encodeObjectKey(objectKey)
	hostHeader := endpoint.Host

	signedHeaders := "content-type;host"
	queryParams := map[string]string{
		"X-Amz-Algorithm":     "AWS4-HMAC-SHA256",
		"X-Amz-Credential":    credentialValue,
		"X-Amz-Date":          amzDate,
		"X-Amz-Expires":       strconv.Itoa(expiresSeconds),
		"X-Amz-SignedHeaders": signedHeaders,
	}
	canonicalQuery := canonicalQueryString(queryParams)

	canonicalHeaders := "content-type:" + contentType + "\n" +
		"host:" + strings.ToLower(hostHeader) + "\n"

	canonicalRequest := strings.Join([]string{
		"PUT",
		canonicalURI,
		canonicalQuery,
		canonicalHeaders,
		signedHeaders,
		"UNSIGNED-PAYLOAD",
	}, "\n")

	stringToSign := strings.Join([]string{
		"AWS4-HMAC-SHA256",
		amzDate,
		credentialScope,
		hexSHA256(canonicalRequest),
	}, "\n")

	signingKey := buildSigningKey(cfg.r2SecretAccessKey, shortDate, cfg.r2SigningRegion, "s3")
	signature := hex.EncodeToString(hmacSHA256(signingKey, stringToSign))

	presignedURL := endpoint.Scheme + "://" + endpoint.Host + canonicalURI + "?" + canonicalQuery + "&X-Amz-Signature=" + percentEncode(signature)
	return presignedURL, nil
}

func canonicalQueryString(values map[string]string) string {
	keys := make([]string, 0, len(values))
	for k := range values {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		parts = append(parts, percentEncode(key)+"="+percentEncode(values[key]))
	}
	return strings.Join(parts, "&")
}

func buildSigningKey(secret, shortDate, region, service string) []byte {
	kDate := hmacSHA256([]byte("AWS4"+secret), shortDate)
	kRegion := hmacSHA256(kDate, region)
	kService := hmacSHA256(kRegion, service)
	return hmacSHA256(kService, "aws4_request")
}

func hmacSHA256(key []byte, data string) []byte {
	h := hmac.New(sha256.New, key)
	_, _ = h.Write([]byte(data))
	return h.Sum(nil)
}

func hexSHA256(value string) string {
	h := sha256.Sum256([]byte(value))
	return hex.EncodeToString(h[:])
}

func buildPublicObjectURL(baseURL, objectKey string) (string, error) {
	parsed, err := url.Parse(strings.TrimSpace(baseURL))
	if err != nil {
		return "", err
	}

	segments := strings.Split(strings.TrimPrefix(objectKey, "/"), "/")
	for i, seg := range segments {
		segments[i] = percentEncode(seg)
	}
	parsed.Path = strings.TrimRight(parsed.Path, "/") + "/" + strings.Join(segments, "/")
	return parsed.String(), nil
}

func encodeObjectKey(key string) string {
	parts := strings.Split(strings.TrimPrefix(key, "/"), "/")
	for i, part := range parts {
		parts[i] = percentEncode(part)
	}
	return strings.Join(parts, "/")
}

func encodePathSegment(segment string) string {
	return percentEncode(strings.Trim(segment, "/"))
}

func percentEncode(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		ch := s[i]
		if isUnreserved(ch) {
			b.WriteByte(ch)
		} else {
			b.WriteString("%")
			b.WriteString(strings.ToUpper(hex.EncodeToString([]byte{ch})))
		}
	}
	return b.String()
}

func isUnreserved(ch byte) bool {
	if ch >= 'A' && ch <= 'Z' {
		return true
	}
	if ch >= 'a' && ch <= 'z' {
		return true
	}
	if ch >= '0' && ch <= '9' {
		return true
	}
	switch ch {
	case '-', '_', '.', '~':
		return true
	default:
		return false
	}
}

func randomHex(bytesLen int) string {
	buf := make([]byte, bytesLen)
	if _, err := rand.Read(buf); err != nil {
		// Fallback to timestamp-derived value if crypto random fails.
		return strconv.FormatInt(time.Now().UnixNano(), 16)
	}
	return hex.EncodeToString(buf)
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
