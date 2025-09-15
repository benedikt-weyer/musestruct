use sea_orm::entity::prelude::*;
use sea_orm::{Set, ActiveModelBehavior};
use serde::{Deserialize, Serialize};
use uuid::{Uuid, Timestamp};
use chrono::{DateTime, Utc, NaiveDateTime};
use async_trait::async_trait;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "playlist_songs")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub playlist_id: Uuid,
    pub song_id: Uuid,
    pub position: i32,
    pub added_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::playlist::Entity",
        from = "Column::PlaylistId",
        to = "super::playlist::Column::Id"
    )]
    Playlist,
    #[sea_orm(
        belongs_to = "super::song::Entity",
        from = "Column::SongId",
        to = "super::song::Column::Id"
    )]
    Song,
}

impl Related<super::playlist::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Playlist.def()
    }
}

impl Related<super::song::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Song.def()
    }
}

#[async_trait]
impl ActiveModelBehavior for ActiveModel {
    fn new() -> Self {
        Self {
            id: Set(Uuid::new_v7(Timestamp::now(uuid::NoContext))),
            added_at: Set(chrono::Utc::now().naive_utc()),
            ..ActiveModelTrait::default()
        }
    }
}

#[derive(Debug, Serialize)]
pub struct PlaylistSongResponseDto {
    pub id: Uuid,
    pub playlist_id: Uuid,
    pub song_id: Uuid,
    pub position: i32,
    pub added_at: NaiveDateTime,
}

impl From<Model> for PlaylistSongResponseDto {
    fn from(playlist_song: Model) -> Self {
        Self {
            id: playlist_song.id,
            playlist_id: playlist_song.playlist_id,
            song_id: playlist_song.song_id,
            position: playlist_song.position,
            added_at: playlist_song.added_at,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct AddSongToPlaylistDto {
    pub song_id: Uuid,
    pub position: Option<i32>,
}
