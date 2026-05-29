# Caching Strategies

This page documents the caching mechanisms that currently exist in the backend.

The source of truth for this page is the live Rust implementation under `apps/backend/src`, not an intended future architecture.

## Overview

The current cache-related behavior is concentrated in the backend and falls into five categories:

- downloaded stream files cached on disk for non-server providers
- extracted local cover art cached on disk
- remote provider cover art cached on disk and served back through the backend
- Tidal album cover URLs cached in memory
- generated spectrogram and analysis images written to disk

There is no centralized cache service such as Redis, and there is no database-backed cache table at the moment.

## Cache Matrix

| Layer | Scope | Storage | Reuse policy | Cleanup policy |
| --- | --- | --- | --- | --- |
| Streaming track cache | Non-server stream playback | `./cache/*.mp3` plus in-memory index | Reused only while the in-memory index entry is still valid | Startup cleanup for age and size |
| Local cover cache | Embedded artwork from local audio files | `./cache/covers/*` | Reused when the hashed cover file already exists | No explicit cleanup |
| Provider cover cache | Remote artwork URLs from Spotify, Tidal, and Qobuz responses | `./cache/provider_covers/*` plus backend cover-proxy URLs | Reused until the cached file becomes older than one year; stale files are still served if refresh fails | No explicit cleanup |
| Tidal album cover cache | Tidal cover URL lookups | Process memory | Reused for the life of the backend process | Cleared only on restart |
| Spectrogram artifacts | BPM/spectrogram analysis output | `./cache/spectrograms/*.png` | Persisted on disk, but currently overwritten instead of reused | No explicit cleanup |
| HTTP response caching | Stream and cover responses | Client/proxy caches via headers | Controlled by `Cache-Control` headers | Expires client-side |

## Streaming Track Cache

The backend stream cache is implemented in `apps/backend/src/services/streaming_service.rs` and initialized from `apps/backend/src/main.rs` with `./cache` as the cache root.

Current behavior:

- It is used for non-server provider playback through `GET /api/streaming/backend-stream-url`.
- Server/local tracks explicitly bypass this cache and return their direct local stream URL instead.
- Cached files are written as `./cache/<cache_key>.mp3`.
- The cache key is deterministic:
  - preferred key: SHA-256 of `source|artist|title`
  - fallback key: `source_trackId`
- Cache entries are tracked in an in-memory `HashMap<String, CachedTrack>`.

Validity and limits:

- Maximum cache size is `5 GiB`.
- Maximum cache age is `24 hours`.
- A cached track is considered valid only if:
  - the file still exists on disk
  - the entry age is not older than `24 hours`

Cleanup behavior:

- The cache directory is created on startup.
- Startup cleanup removes files older than `24 hours`.
- If total size is still above the configured limit, the oldest files are removed.

Important limitation:

- The lookup index is in memory only and is not rebuilt from disk on startup.
- That means old `.mp3` files may still exist in `./cache`, but they are not reused after a backend restart unless a new request repopulates the in-memory map and rewrites the same deterministic file path.

## Local Cover Art Cache

Local cover extraction is implemented in `apps/backend/src/services/streaming/local.rs`.

Current behavior:

- When local audio metadata is read, the backend first tries to extract embedded artwork from the audio file.
- Extracted artwork is cached under `./cache/covers`.
- The cache key is a SHA-256 hash of the audio file path.
- If a cached image already exists with a supported extension (`jpg`, `jpeg`, or `png`), the backend returns the cached cover URL immediately.
- Cached cover URLs are exposed as `/api/stream/local/cover/cached/<filename>`.

Fallback behavior:

- If no embedded artwork is available, the backend falls back to direct image files inside `own_music`, such as `cover.jpg`, `folder.png`, or a same-stem image next to the audio file.
- Those direct files are served, but they are not copied into the cache directory.

Current limitation:

- There is no TTL, size cap, or scheduled cleanup for `./cache/covers` in the current implementation.

## Provider Cover Art Cache

Remote provider cover caching is implemented in `apps/backend/src/services/cover_cache.rs` and exposed from `apps/backend/src/handlers/streaming.rs`.

Current behavior:

- Remote `http` and `https` cover URLs are normalized into backend-owned URLs of the form `/api/stream/cover/provider?url=<encoded-remote-url>`.
- The backend only rewrites remote provider artwork URLs. Existing local/server cover URLs under `/api/stream/local/cover/...` are left unchanged.
- Provider cover images are cached under `./cache/provider_covers`.
- The cache key is a SHA-256 hash of the original remote URL.
- The backend stores the image using an extension derived from the response content type or, if necessary, from the remote URL path.
- The configured TTL is `31536000` seconds, which is one year.

Reuse and refresh behavior:

- If a cached provider image exists and is younger than one year, the backend serves it directly.
- If the cached file is older than one year, the backend tries to refresh it from the provider.
- If that refresh fails but an old cached file still exists, the backend serves the stale cached copy instead of failing the request.

Where it is used:

- search results from `/api/streaming/search`
- single-track responses from `/api/streaming/track`
- provider playlist-track and album-track responses
- saved track, playlist-item, and queue responses that surface provider artwork back to the app

## Tidal Album Cover URL Cache

Tidal album cover URL caching is implemented in `apps/backend/src/services/streaming/tidal.rs`.

Current behavior:

- The backend keeps a process-local `Mutex<HashMap<String, Option<String>>>` keyed by Tidal album ID.
- It caches both successful lookups and missing results.
- On a cache miss, the backend fetches the Tidal album browse page, extracts the `og:image` value, and stores the result in memory.

Current limitation:

- This cache has no TTL or eviction policy.
- It is not persisted anywhere and is cleared whenever the backend process restarts.

## Spectrogram and Analysis Image Artifacts

Spectrogram BPM analysis output is implemented in `apps/backend/src/services/spectrogram_bpm_analysis.rs`.

Current behavior:

- Spectrogram images are written to `./cache/spectrograms/spectrogram_<file_stem>.png`.
- Analysis visualizations are written to `./cache/spectrograms/analysis_<file_stem>_<bpm>bpm.png`.
- Image generation is currently enabled.
- `OVERRIDE_EXISTING_IMAGES` is currently set to `true`, so existing files are overwritten instead of reused.

Interpretation:

- These files behave more like persistent analysis artifacts than a traditional reusable cache, because the current configuration always regenerates and overwrites them.

Current limitation:

- There is no cleanup or retention policy for `./cache/spectrograms` in the current implementation.

## HTTP Cache Headers

The backend also sets HTTP cache headers on streamed content:

- Cached provider streams served from `/api/stream/{track_id}` use `Cache-Control: public, max-age=3600`.
- Direct local audio streams served from `/api/stream/local/{path}` also use `Cache-Control: public, max-age=3600`.
- Local cover image responses served from `/api/stream/local/cover/{path}` use `Cache-Control: public, max-age=31536000`.
- Provider cover image responses served from `/api/stream/cover/provider` use `Cache-Control: public, max-age=31536000`.

These headers allow browser, device, or proxy-level caching even when the backend itself is not maintaining a persistent application-level cache for the same resource.

## What Is Not Currently Cached

Based on the current backend code, there is no dedicated cache layer for:

- aggregated search results across providers
- playlist query responses
- saved library API responses
- queue state in memory beyond normal request handling
- provider auth metadata beyond the persisted `user_streaming_services` table

Notes:

- The server/local source now also has a database-backed provider cache family (`server_tracks`, `server_albums`, `server_playlists`, and join tables), but those tables are part of the data model, not a generic cache service.
- There is still no Redis-style centralized cache and no dedicated database table used purely for cover-art or search-result caching.

If those behaviors change later, this page should be updated from the implementation rather than from architectural intent.