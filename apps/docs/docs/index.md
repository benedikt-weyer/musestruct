# Musestruct Docs

This documentation site covers the current workspace layout, backend setup, and provider integration steps for the active Musestruct repository.

## What is in this docs app

- A current high-level overview of the repo and runtime pieces.
- Backend setup guidance that matches the live Rust backend and React Native client.
- Provider setup guides for Spotify and Tidal.
- Local/server source instructions for the backend-managed music directory.

## Quick start

1. Install the MkDocs dependencies:
   ```bash
   cd apps/docs
   python -m pip install -r requirements.txt
   ```
2. Start the docs site locally:
   ```bash
   cd apps/docs
   mkdocs serve -f mkdocs.yml
   ```
3. Open `http://127.0.0.1:8000`.

If you are using the repo's current Nix-based environment, the easiest path is the workspace script, which runs MkDocs through `uv`:

```bash
npm run docs
```

The docs app also exposes `dev`, `build`, and `check` scripts through its local `package.json`.

## Recommended reading order

1. [Setup Overview](setup-overview.md)
2. [Spotify](providers/spotify.md)
3. [Tidal](providers/tidal.md)
4. [Server / Local Source](sources/server-local.md)
