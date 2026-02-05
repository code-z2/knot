# Cloudflare Image Upload Worker (Go)

This service mints Cloudflare Images direct-upload URLs for the iOS client.

Production base URL: `https://upload.peteranyaogu.com`

## Endpoints

- `GET /health`
- `POST /v1/images/direct-upload`

## Request

```json
{
  "eoaAddress": "0x...",
  "fileName": "avatar-uuid.jpg",
  "contentType": "image/jpeg"
}
```

## Response

```json
{
  "uploadURL": "https://upload.imagedelivery.net/...",
  "imageID": "...",
  "deliveryURL": "https://imagedelivery.net/<hash>/<image-id>/public"
}
```

## Required Environment Variables

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_IMAGES_API_TOKEN`
- `CLOUDFLARE_IMAGES_DELIVERY_HASH`
- `UPLOAD_CLIENT_TOKEN`

## Optional Environment Variables

- `PORT` (default: `8080`)
- `ALLOWED_ORIGIN` (default: `*`)
- `DIRECT_UPLOAD_EXPIRY_SECONDS` (default: `600`, valid range `60..3600`)

## Local Run

```bash
cd packages/cloudflare-image-upload-worker
PORT=8080 \
UPLOAD_CLIENT_TOKEN=dev-token \
CLOUDFLARE_ACCOUNT_ID=... \
CLOUDFLARE_IMAGES_API_TOKEN=... \
CLOUDFLARE_IMAGES_DELIVERY_HASH=... \
go run .
```

## Notes

- iOS calls this service first, then uploads multipart bytes directly to Cloudflare using the returned `uploadURL`.
- Cloudflare API credentials stay on backend only.
- Use TLS and tighten `ALLOWED_ORIGIN` in production.
