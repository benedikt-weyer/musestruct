use sea_orm::entity::prelude::*;
use sea_orm::{Set, ActiveModelBehavior};
use serde::{Deserialize, Serialize};
use uuid::{Uuid, Timestamp};
use chrono::NaiveDateTime;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "queue_items")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub user_id: Uuid,
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: i32, // in seconds
    pub source: String, // "spotify", "qobuz", etc.
    pub cover_url: Option<String>,
    pub position: i32, // position in queue (0-based)
    pub added_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "crate::models::user::Entity",
        from = "Column::UserId",
        to = "crate::models::user::Column::Id"
    )]
    User,
}

impl Related<crate::models::user::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::User.def()
    }
}

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
pub struct QueueItemResponseDto {
    pub id: Uuid,
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: i32,
    pub source: String,
    pub cover_url: Option<String>,
    pub position: i32,
    pub added_at: NaiveDateTime,
}

impl From<Model> for QueueItemResponseDto {
    fn from(item: Model) -> Self {
        Self {
            id: item.id,
            track_id: item.track_id,
            title: item.title,
            artist: item.artist,
            album: item.album,
            duration: item.duration,
            source: item.source,
            cover_url: item.cover_url,
            position: item.position,
            added_at: item.added_at,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct AddToQueueDto {
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: i32,
    pub source: String,
    pub cover_url: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ReorderQueueDto {
    pub item_id: Uuid,
    pub new_position: i32,
}
