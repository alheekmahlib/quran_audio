---
title: Quran Muaalem Recitation Correction
emoji: 🕌
colorFrom: green
colorTo: blue
sdk: gradio
app_file: app.py
pinned: false
license: mit
---

# 🕌 Quran Muaalem — Recitation Correction Server

Self-hosted server for [quran-muaalem](https://github.com/obadx/quran-muaalem) —
AI-powered Quran recitation correction with tajweed error detection.

This Space provides the HTTP API used by the
[`quran_audio`](https://github.com/alheekmahlib/quran_audio) Flutter library's
recitation feature.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/correct-recitation` | Correct a recitation (audio → tajweed errors) |
| `POST` | `/search` | Locate audio position in the Quran |
| `POST` | `/transcript` | Audio → phonemes only |
| `GET` | `/health` | Server health check |

## Usage

```bash
curl -X POST "https://YOUR_USERNAME-quran-muaalem.hf.space/correct-recitation" \
    -F "file=@recitation.wav" \
    -F "error_ratio=0.3"
```

## Notes

- On free CPU tier: expect **10-30s** per recitation (model is 2.4GB).
- Enable GPU in Space settings for **<1s** response time.
- The model auto-downloads on first startup (~2.4GB, takes a few minutes).
- Spaces sleep after 48h of inactivity; the first request after sleep wakes it
  (takes ~30s).
