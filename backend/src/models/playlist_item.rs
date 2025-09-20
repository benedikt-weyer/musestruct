use sea_orm::entity::prelude::*;
use serde::{Deserialize, Serialize};
use chrono::NaiveDateTime;
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "playlist_items")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub playlist_id: Uuid,
    pub item_type: String, // "track" or "playlist"
    pub item_id: String, // track_id or playlist_id
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
}

impl Related<super::playlist::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Playlist.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}

#[derive(Deserialize)]
pub struct AddPlaylistItemDto {
    pub item_type: String, // "track" or "playlist"
    pub item_id: String,
    pub position: Option<i32>,
}

#[derive(Deserialize)]
pub struct ReorderPlaylistItemDto {
    pub new_position: i32,
}

#[derive(Serialize)]
pub struct PlaylistItemResponseDto {
    pub id: Uuid,
    pub item_type: String,
    pub item_id: String,
    pub position: i32,
    pub added_at: NaiveDateTime,
    // Additional fields for display
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub duration: Option<i32>,
    pub source: Option<String>,
    pub cover_url: Option<String>,
    pub is_playlist: bool,
    pub playlist_name: Option<String>,
}

impl From<Model> for PlaylistItemResponseDto {
    fn from(model: Model) -> Self {
        Self {
            id: model.id,
            item_type: model.item_type.clone(),
            item_id: model.item_id.clone(),
            position: model.position,
            added_at: model.added_at,
            title: None,
            artist: None,
            album: None,
            duration: None,
            source: None,
            cover_url: None,
            is_playlist: model.item_type == "playlist",
            playlist_name: None,
        }
    }
}
