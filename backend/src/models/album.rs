use sea_orm::entity::prelude::*;
use sea_orm::{Set, ActiveModelBehavior};
use serde::{Deserialize, Serialize};
use uuid::{Uuid, Timestamp};
use chrono::{DateTime, Utc, NaiveDateTime};
use async_trait::async_trait;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "albums")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub title: String,
    pub artist: String,
    pub release_date: Option<Date>,
    pub cover_url: Option<String>,
    pub external_id: Option<String>, // For streaming service IDs
    pub source: String, // "local", "qobuz", etc.
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(has_many = "super::song::Entity")]
    Songs,
}

impl Related<super::song::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Songs.def()
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
pub struct AlbumResponseDto {
    pub id: Uuid,
    pub title: String,
    pub artist: String,
    pub release_date: Option<Date>,
    pub cover_url: Option<String>,
    pub source: String,
    pub created_at: NaiveDateTime,
}

impl From<Model> for AlbumResponseDto {
    fn from(album: Model) -> Self {
        Self {
            id: album.id,
            title: album.title,
            artist: album.artist,
            release_date: album.release_date,
            cover_url: album.cover_url,
            source: album.source,
            created_at: album.created_at,
        }
    }
}
