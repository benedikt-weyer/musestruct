use sea_orm::entity::prelude::*;
use serde::{Deserialize, Serialize};
use chrono::NaiveDateTime;
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "playlists")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub is_public: bool,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(has_many = "super::playlist_item::Entity")]
    PlaylistItems,
}

impl Related<super::playlist_item::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::PlaylistItems.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}

#[derive(Deserialize)]
pub struct CreatePlaylistDto {
    pub name: String,
    pub description: Option<String>,
    pub is_public: bool,
}

#[derive(Deserialize)]
pub struct UpdatePlaylistDto {
    pub name: Option<String>,
    pub description: Option<String>,
    pub is_public: Option<bool>,
}

#[derive(Serialize)]
pub struct PlaylistResponseDto {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub is_public: bool,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub item_count: i32,
}

impl From<Model> for PlaylistResponseDto {
    fn from(model: Model) -> Self {
        Self {
            id: model.id,
            name: model.name,
            description: model.description,
            is_public: model.is_public,
            created_at: model.created_at,
            updated_at: model.updated_at,
            item_count: 0, // Will be set separately
        }
    }
}