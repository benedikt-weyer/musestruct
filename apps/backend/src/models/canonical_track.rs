use async_trait::async_trait;
use chrono::NaiveDateTime;
use sea_orm::entity::prelude::*;
use sea_orm::{ActiveModelBehavior, Set};
use serde::{Deserialize, Serialize};
use uuid::{Timestamp, Uuid};

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "canonical_tracks")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub title: String,
    pub artist: String,
    pub album_name: Option<String>,
    pub duration: Option<i32>,
    pub cover_url: Option<String>,
    pub normalized_title: String,
    pub normalized_artist: String,
    pub spotify_track_id: Option<Uuid>,
    pub tidal_track_id: Option<Uuid>,
    pub qobuz_track_id: Option<Uuid>,
    pub server_track_id: Option<Uuid>,
    pub match_status: String,
    pub unresolved_reason: Option<String>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

#[async_trait]
impl ActiveModelBehavior for ActiveModel {
    fn new() -> Self {
        Self {
            id: Set(Uuid::new_v7(Timestamp::now(uuid::NoContext))),
            match_status: Set("resolved".to_string()),
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