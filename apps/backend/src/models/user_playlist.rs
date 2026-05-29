use async_trait::async_trait;
use chrono::NaiveDateTime;
use sea_orm::entity::prelude::*;
use sea_orm::{ActiveModelBehavior, Set};
use serde::{Deserialize, Serialize};
use uuid::{Timestamp, Uuid};

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "user_playlists")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub user_id: Uuid,
    pub canonical_playlist_id: Option<Uuid>,
    pub source: Option<String>,
    pub provider_playlist_id: Option<String>,
    pub name: String,
    pub description: Option<String>,
    pub is_public: bool,
    pub is_read_only: bool,
    pub is_watched: bool,
    pub last_synced_at: Option<NaiveDateTime>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "crate::models::user::Entity",
        from = "Column::UserId",
        to = "crate::models::user::Column::Id"
    )]
    User,
    #[sea_orm(
        belongs_to = "super::canonical_playlist::Entity",
        from = "Column::CanonicalPlaylistId",
        to = "super::canonical_playlist::Column::Id"
    )]
    CanonicalPlaylist,
}

impl Related<crate::models::user::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::User.def()
    }
}

impl Related<super::canonical_playlist::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::CanonicalPlaylist.def()
    }
}

#[async_trait]
impl ActiveModelBehavior for ActiveModel {
    fn new() -> Self {
        Self {
            id: Set(Uuid::new_v7(Timestamp::now(uuid::NoContext))),
            is_public: Set(false),
            is_read_only: Set(false),
            is_watched: Set(false),
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