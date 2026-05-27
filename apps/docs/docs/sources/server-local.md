# Server / Local Source Setup

## Two different local-source concepts in this repo

There are two separate local music concepts in the current workspace:

### 1. Backend-managed local source

This is the backend `server` source exposed through the streaming abstraction.

- It is scanned by the Rust backend.
- It recursively indexes audio files from the backend's `own_music` directory.
- It supports file metadata extraction from tags and folder structure.

### 2. React Native on-device folder access

This is the folder picker in the React Native Settings screen.

- It stores a user-selected folder on the device.
- It is used by the app’s native folder access module.
- It is separate from the backend `server` source.

If you want the backend `server` source to find music, you need to populate the backend directory described below. Picking a folder in the app does not automatically sync files into the backend.

## Backend-managed local source setup

The backend creates and scans its music directory relative to its working directory. With the current development script, that means:

```text
apps/backend/own_music
```

### Steps

1. Start with the backend stopped.
2. Create the directory if it does not exist:
   ```bash
   mkdir -p apps/backend/own_music
   ```
3. Copy or symlink your test music into that directory.
4. Start the backend:
   ```bash
   scripts/start-backend.sh
   ```
5. Use the app against that backend and select the `server` source where applicable.

## Supported file types

The backend local music scanner currently looks for these file extensions:

- `mp3`
- `flac`
- `wav`
- `m4a`
- `ogg`

It scans directories recursively, so nested artist and album folders are fine.

## React Native device folder access setup

If you want the app to read playable files directly from a folder on the device:

1. Open the React Native app.
2. Go to Settings.
3. Use **Choose music folder**.
4. Grant the required Android folder access permissions.

This device-side folder access is useful for app-local browsing, but it is not the same as the backend `server` source.

## Troubleshooting

### The backend local source is empty

Check these points:

- your files are under `apps/backend/own_music`
- the file extensions are one of the supported formats above
- the backend process is running from the normal development script
- the files are readable by the backend process

### Metadata looks incomplete

The backend first tries embedded audio tags and then falls back to filename and folder structure parsing. Tracks without complete tags may still appear, but with less accurate album or artist data.
