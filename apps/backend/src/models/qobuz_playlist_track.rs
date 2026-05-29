use chrono::NaiveDateTime;
use sea_orm::entity::prelude::*;
use sea_orm::{ActiveModelBehavior, Set};
use serde::{Deserialize, Serialize};
use uuid::{Timestamp, Uuid};

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "qobuz_playlist_tracks")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub playlist_id: Uuid,
    pub track_id: Uuid,
    pub position: i32,
    pub added_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(belongs_to = "super::qobuz_playlist::Entity", from = "Column::PlaylistId", to = "super::qobuz_playlist::Column::Id")]
    Playlist,
    #[sea_orm(belongs_to = "super::qobuz_track::Entity", from = "Column::TrackId", to = "super::qobuz_track::Column::Id")]
    Track,
}

impl Related<super::qobuz_playlist::Entity> for Entity { fn to() -> RelationDef { Relation::Playlist.def() } }
impl Related<super::qobuz_track::Entity> for Entity { fn to() -> RelationDef { Relation::Track.def() } }

impl ActiveModelBehavior for ActiveModel {
    fn new() -> Self {
        Self { id: Set(Uuid::new_v7(Timestamp::now(uuid::NoContext))), added_at: Set(chrono::Utc::now().naive_utc()), ..ActiveModelTrait::default() }
    }
}