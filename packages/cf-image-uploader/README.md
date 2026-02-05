# R2 Image Upload Service (Go)

This service mints Cloudflare R2 presigned upload URLs for the iOS client.

Production base URL (API): `https://upload.peteranyaogu.com`

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
  "uploadURL": "https://<account>.r2.cloudflarestorage.com/<bucket>/...",
  "imageID": "avatars/0x.../20260205-123000-ab12cd-avatar-uuid.jpg",
  "deliveryURL": "https://<public-r2-domain>/avatars/0x.../20260205-123000-ab12cd-avatar-uuid.jpg"
}
```

## Required Environment Variables

- `UPLOAD_CLIENT_TOKEN`
- `R2_ACCOUNT_ID`
- `R2_BUCKET_NAME`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_PUBLIC_BASE_URL`

## Optional Environment Variables

- `PORT` (default: `8080`)
- `ALLOWED_ORIGIN` (default: `*`)
- `DIRECT_UPLOAD_EXPIRY_SECONDS` (default: `600`, valid range `60..3600`)
- `R2_S3_ENDPOINT` (default: `https://<R2_ACCOUNT_ID>.r2.cloudflarestorage.com`)

## Local Run

```bash
cd packages/cf-image-uploader
PORT=8080 \
UPLOAD_CLIENT_TOKEN=dev-token \
R2_ACCOUNT_ID=... \
R2_BUCKET_NAME=... \
R2_ACCESS_KEY_ID=... \
R2_SECRET_ACCESS_KEY=... \
R2_PUBLIC_BASE_URL=https://pub-xxxx.r2.dev \
go run .
```

## Notes

- iOS calls this service, then uploads raw bytes to the returned presigned `uploadURL` with `PUT`.
- The app stores `deliveryURL` in ENS `avatar` record.
- Keep `UPLOAD_CLIENT_TOKEN` short-lived in production (for hackathon a static token is acceptable).
