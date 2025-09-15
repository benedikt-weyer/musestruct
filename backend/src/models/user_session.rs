use sea_orm::entity::prelude::*;
use sea_orm::{Set, ActiveModelBehavior};
use serde::{Deserialize, Serialize};
use uuid::{Uuid, Timestamp};
use chrono::{DateTime, Utc, NaiveDateTime, Duration};

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "user_sessions")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: Uuid,
    pub user_id: Uuid,
    pub session_token: String,
    pub expires_at: NaiveDateTime,
    pub created_at: NaiveDateTime,
    pub is_active: bool,
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

impl ActiveModelBehavior for ActiveModel {
    fn new() -> Self {
        Self {
            id: Set(Uuid::new_v7(Timestamp::now(uuid::NoContext))),
            created_at: Set(chrono::Utc::now().naive_utc()),
            expires_at: Set((chrono::Utc::now() + Duration::days(7)).naive_utc()), // 7 days default
            is_active: Set(true),
            ..ActiveModelTrait::default()
        }
    }
}
