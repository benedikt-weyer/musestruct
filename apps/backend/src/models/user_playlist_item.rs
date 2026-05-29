use chrono::NaiveDateTime;
use sea_orm::entity::prelude::*;
use sea_orm::{ActiveModelBehavior, Set};
use serde::{Deserialize, Serialize};
use uuid::{Timestamp, Uuid};

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "user_playlist_items")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub playlist_id: Uuid,
    pub item_type: String,
    pub user_track_id: Option<Uuid>,
    pub nested_playlist_id: Option<Uuid>,
    pub position: i32,
    pub created_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::user_playlist::Entity",
        from = "Column::PlaylistId",
        to = "super::user_playlist::Column::Id"
    )]
    Playlist,
    #[sea_orm(
        belongs_to = "super::user_track::Entity",
        from = "Column::UserTrackId",
        to = "super::user_track::Column::Id"
    )]
    UserTrack,
    #[sea_orm(
        belongs_to = "super::user_playlist::Entity",
        from = "Column::NestedPlaylistId",
        to = "super::user_playlist::Column::Id"
    )]
    NestedPlaylist,
}

impl Related<super::user_playlist::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Playlist.def()
    }
}

impl Related<super::user_track::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::UserTrack.def()
    }
}

impl ActiveModelBehavior for ActiveModel {
    fn new() -> Self {
        Self {
            id: Set(Uuid::new_v7(Timestamp::now(uuid::NoContext))),
            created_at: Set(chrono::Utc::now().naive_utc()),
            ..ActiveModelTrait::default()
        }
    }
}