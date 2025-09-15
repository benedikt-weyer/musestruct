pub mod user;
pub mod album;
pub mod song;
pub mod playlist;
pub mod playlist_song;
pub mod streaming_service;
pub mod user_session;

// Re-export specific entities to avoid namespace conflicts
pub use user::{Entity as UserEntity, Model as UserModel, ActiveModel as UserActiveModel, Column as UserColumn};
pub use album::{Entity as AlbumEntity, Model as AlbumModel, ActiveModel as AlbumActiveModel, Column as AlbumColumn};
pub use song::{Entity as SongEntity, Model as SongModel, ActiveModel as SongActiveModel, Column as SongColumn};
pub use playlist::{Entity as PlaylistEntity, Model as PlaylistModel, ActiveModel as PlaylistActiveModel, Column as PlaylistColumn};
pub use playlist_song::{Entity as PlaylistSongEntity, Model as PlaylistSongModel, ActiveModel as PlaylistSongActiveModel, Column as PlaylistSongColumn};
pub use streaming_service::{Entity as StreamingServiceEntity, Model as StreamingServiceModel, ActiveModel as StreamingServiceActiveModel, Column as StreamingServiceColumn};
pub use user_session::{Entity as UserSessionEntity, Model as UserSessionModel, ActiveModel as UserSessionActiveModel, Column as UserSessionColumn};

// Re-export DTOs without prefix
pub use user::{CreateUserDto, LoginDto, UserResponseDto};
pub use album::AlbumResponseDto;
pub use song::{SongResponseDto, SearchQuery};
pub use playlist::{PlaylistResponseDto, CreatePlaylistDto};
pub use playlist_song::{PlaylistSongResponseDto, AddSongToPlaylistDto};
pub use streaming_service::{StreamingServiceResponseDto, ConnectServiceDto};
