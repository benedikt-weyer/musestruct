use chrono::NaiveDateTime;
use sea_orm::entity::prelude::*;
use sea_orm::{ActiveModelBehavior, Set};
use serde::{Deserialize, Serialize};
use uuid::{Timestamp, Uuid};

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "server_album_tracks")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub album_id: Uuid,
    pub track_id: Uuid,
    pub position: i32,
    pub created_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(belongs_to = "super::server_album::Entity", from = "Column::AlbumId", to = "super::server_album::Column::Id")]
    Album,
    #[sea_orm(belongs_to = "super::server_track::Entity", from = "Column::TrackId", to = "super::server_track::Column::Id")]
    Track,
}

impl Related<super::server_album::Entity> for Entity { fn to() -> RelationDef { Relation::Album.def() } }
impl Related<super::server_track::Entity> for Entity { fn to() -> RelationDef { Relation::Track.def() } }

impl ActiveModelBehavior for ActiveModel {
    fn new() -> Self {
        Self { id: Set(Uuid::new_v7(Timestamp::now(uuid::NoContext))), created_at: Set(chrono::Utc::now().naive_utc()), ..ActiveModelTrait::default() }
    }
}