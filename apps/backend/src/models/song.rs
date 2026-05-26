use sea_orm::entity::prelude::*;
use sea_orm::{Set, ActiveModelBehavior};
use serde::{Deserialize, Serialize};
use uuid::{Uuid, Timestamp};
use chrono::{DateTime, Utc, NaiveDateTime};
use async_trait::async_trait;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "songs")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub title: String,
    pub artist: String,
    pub album_id: Option<Uuid>,
    pub duration: Option<i32>, // duration in seconds
    pub track_number: Option<i32>,
    pub external_id: Option<String>, // For streaming service IDs
    pub stream_url: Option<String>,
    pub local_path: Option<String>,
    pub source: String, // "local", "qobuz", etc.
    pub quality: Option<String>, // "lossy", "lossless", "hi-res"
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::album::Entity",
        from = "Column::AlbumId",
        to = "super::album::Column::Id"
    )]
    Album,
}

impl Related<super::album::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Album.def()
    }
}

#[async_trait]
impl ActiveModelBehavior for ActiveModel {
    fn new() -> Self {
        Self {
            id: Set(Uuid::new_v7(Timestamp::now(uuid::NoContext))),
            created_at: Set(chrono::Utc::now().naive_utc()),
            updated_at: Set(chrono::Utc::now().naive_utc()),
            ..ActiveModelTrait::default()
        }
    }

    async fn before_save<C>(mut self, _db: &C, _insert: bool) -> Result<Self, DbErr>
    where
        C: ConnectionTrait,
    {
        self.updated_at = Set(chrono::Utc::now().naive_utc());
        Ok(self)
    }
}

#[derive(Debug, Serialize)]
pub struct SongResponseDto {
    pub id: Uuid,
    pub title: String,
    pub artist: String,
    pub album_id: Option<Uuid>,
    pub duration: Option<i32>,
    pub track_number: Option<i32>,
    pub stream_url: Option<String>,
    pub source: String,
    pub quality: Option<String>,
    pub created_at: NaiveDateTime,
}

impl From<Model> for SongResponseDto {
    fn from(song: Model) -> Self {
        Self {
            id: song.id,
            title: song.title,
            artist: song.artist,
            album_id: song.album_id,
            duration: song.duration,
            track_number: song.track_number,
            stream_url: song.stream_url,
            source: song.source,
            quality: song.quality,
            created_at: song.created_at,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    pub query: String,
    pub limit: Option<u64>,
    pub offset: Option<u64>,
}
