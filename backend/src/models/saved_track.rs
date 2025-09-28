use sea_orm::entity::prelude::*;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "saved_track")]
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
    pub bpm: Option<f32>, // Beats per minute
    pub key_name: Option<String>, // Musical key in standard notation (e.g., "C#", "Am")
    pub camelot: Option<String>, // Camelot notation (e.g., "8A", "9B")
    pub key_confidence: Option<f32>, // Key detection confidence (0.0 to 1.0)
    pub created_at: chrono::NaiveDateTime,
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

impl ActiveModelBehavior for ActiveModel {}
