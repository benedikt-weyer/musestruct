use sea_orm::entity::prelude::*;
use sea_orm::{Set, ActiveModelBehavior};
use serde::{Deserialize, Serialize};
use uuid::{Uuid, Timestamp};
use chrono::{DateTime, Utc, NaiveDateTime};
use async_trait::async_trait;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "user_streaming_services")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub user_id: Uuid,
    pub service_name: String, // "qobuz", "spotify", "tidal", etc.
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    pub expires_at: Option<NaiveDateTime>,
    pub is_active: bool,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::user::Entity",
        from = "Column::UserId",
        to = "super::user::Column::Id"
    )]
    User,
}

impl Related<super::user::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::User.def()
    }
}

#[async_trait]
impl ActiveModelBehavior for ActiveModel {
    fn new() -> Self {
        Self {
            id: Set(Uuid::new_v7(Timestamp::now(uuid::NoContext))),
            created_at: Set(chrono::Utc::now().naive_utc()),
            updated_at: Set(chrono::Utc::now().naive_utc()),
            is_active: Set(true),
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
pub struct StreamingServiceResponseDto {
    pub id: Uuid,
    pub service_name: String,
    pub is_active: bool,
    pub created_at: NaiveDateTime,
}

impl From<Model> for StreamingServiceResponseDto {
    fn from(service: Model) -> Self {
        Self {
            id: service.id,
            service_name: service.service_name,
            is_active: service.is_active,
            created_at: service.created_at,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct ConnectServiceDto {
    pub service_name: String,
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    pub expires_at: Option<NaiveDateTime>,
}
