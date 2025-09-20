pub mod user;
pub mod album;
pub mod song;
pub mod playlist;
pub mod playlist_item;
pub mod playlist_song;
pub mod streaming_service;
pub mod user_session;
pub mod saved_track;
pub mod queue_item;

// Re-export specific entities to avoid namespace conflicts
pub use user::{Entity as UserEntity, Model as UserModel, ActiveModel as UserActiveModel, Column as UserColumn};
pub use album::{Entity as AlbumEntity, Model as AlbumModel, ActiveModel as AlbumActiveModel, Column as AlbumColumn};
pub use song::{Entity as SongEntity, Model as SongModel, ActiveModel as SongActiveModel, Column as SongColumn};
pub use playlist::{Entity as PlaylistEntity, Model as PlaylistModel, ActiveModel as PlaylistActiveModel, Column as PlaylistColumn};
pub use playlist_item::{Entity as PlaylistItemEntity, Model as PlaylistItemModel, ActiveModel as PlaylistItemActiveModel, Column as PlaylistItemColumn};
pub use playlist_song::{Entity as PlaylistSongEntity, Model as PlaylistSongModel, ActiveModel as PlaylistSongActiveModel, Column as PlaylistSongColumn};
pub use streaming_service::{Entity as StreamingServiceEntity, Model as StreamingServiceModel, ActiveModel as StreamingServiceActiveModel, Column as StreamingServiceColumn};
pub use user_session::{Entity as UserSessionEntity, Model as UserSessionModel, ActiveModel as UserSessionActiveModel, Column as UserSessionColumn};
pub use saved_track::{Entity as SavedTrackEntity, Model as SavedTrackModel, ActiveModel as SavedTrackActiveModel, Column as SavedTrackColumn};
pub use queue_item::{Entity as QueueItemEntity, Model as QueueItemModel, ActiveModel as QueueItemActiveModel, Column as QueueItemColumn};

// Re-export DTOs without prefix
pub use user::{CreateUserDto, LoginDto, UserResponseDto};
pub use album::AlbumResponseDto;
pub use song::{SongResponseDto, SearchQuery};
pub use playlist::{PlaylistResponseDto, CreatePlaylistDto, UpdatePlaylistDto};
pub use playlist_item::{PlaylistItemResponseDto, AddPlaylistItemDto, ReorderPlaylistItemDto};
pub use playlist_song::{PlaylistSongResponseDto, AddSongToPlaylistDto};
pub use streaming_service::{StreamingServiceResponseDto, ConnectServiceDto};
pub use queue_item::{QueueItemResponseDto, AddToQueueDto, ReorderQueueDto};
