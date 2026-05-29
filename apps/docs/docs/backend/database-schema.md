# Database Schema

This page documents the current PostgreSQL schema used by the backend.

The source of truth is the migration set in `apps/backend/src/migrator`, and the ER diagram below reflects the active tables and foreign-key relationships defined there.

## ER Diagram

```mermaid
erDiagram
    users {
        uuid id PK
        string email UK
        string username
        string password_hash
        timestamp created_at
        timestamp updated_at
        boolean is_active
    }

    user_sessions {
        uuid id PK
        uuid user_id FK
        string session_token UK
        timestamp expires_at
        timestamp created_at
        boolean is_active
    }

    user_streaming_services {
        uuid id PK
        uuid user_id FK
        string service_name
        text access_token
        text refresh_token
        timestamp expires_at
        string account_username
        boolean is_active
        timestamp created_at
        timestamp updated_at
    }

    albums {
        uuid id PK
        string title
        string artist
        date release_date
        text cover_url
        string external_id
        string source
        timestamp created_at
        timestamp updated_at
    }

    songs {
        uuid id PK
        uuid album_id FK
        string title
        string artist
        integer duration
        integer track_number
        string external_id
        text stream_url
        text local_path
        string source
        string quality
        timestamp created_at
        timestamp updated_at
    }

    playlists {
        uuid id PK
        uuid user_id FK
        string name
        text description
        boolean is_public
        timestamp created_at
        timestamp updated_at
    }

    playlist_songs {
        uuid id PK
        uuid playlist_id FK
        uuid song_id FK
        integer position
        timestamp added_at
    }

    playlist_items {
        uuid id PK
        uuid playlist_id FK
        string item_type
        string item_id
        integer position
        timestamp added_at
        string title
        string artist
        string album
        integer duration
        string source
        string cover_url
        string playlist_name
    }

    saved_tracks {
        uuid id PK
        uuid user_id FK
        string track_id
        string title
        string artist
        string album
        integer duration
        string source
        string cover_url
        float bpm
        string key_name
        string camelot
        float key_confidence
        timestamp created_at
    }

    saved_albums {
        uuid id PK
        uuid user_id FK
        string album_id
        string title
        string artist
        string release_date
        string cover_url
        string source
        integer track_count
        timestamp created_at
    }

    queue_items {
        uuid id PK
        uuid user_id FK
        string track_id
        string title
        string artist
        string album
        integer duration
        string source
        string cover_url
        integer position
        timestamp added_at
    }

    users ||--o{ user_sessions : has
    users ||--o{ user_streaming_services : connects
    users ||--o{ playlists : owns
    users ||--o{ saved_tracks : saves
    users ||--o{ saved_albums : saves
    users ||--o{ queue_items : queues
    albums ||--o{ songs : contains
    playlists ||--o{ playlist_songs : links
    songs ||--o{ playlist_songs : appears_in
    playlists ||--o{ playlist_items : contains
```

## Notes

- `playlist_items` is the newer polymorphic playlist-content table. `item_type` distinguishes track entries from nested playlist entries, and `item_id` stores the referenced track or playlist identifier without a database-level foreign key.
- `playlist_songs` still exists for the older local-song playlist model, while provider-backed and nested playlist content is represented through `playlist_items`.
- `saved_tracks` stores additional analysis metadata such as BPM and harmonic key fields (`key_name`, `camelot`, and `key_confidence`).
