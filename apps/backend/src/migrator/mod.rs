use sea_orm_migration::prelude::*;

mod m20250115_000001_create_users_table;
mod m20250115_000002_create_user_sessions_table;
mod m20250115_000007_create_user_streaming_services_table;
mod m20250920_124747_add_account_username_to_streaming_services;
mod m20260529_000001_create_provider_canonical_music_schema;
mod m20260529_000002_create_favourite_tracks_table;

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(m20250115_000001_create_users_table::Migration),
            Box::new(m20250115_000002_create_user_sessions_table::Migration),
            Box::new(m20250115_000007_create_user_streaming_services_table::Migration),
            Box::new(m20250920_124747_add_account_username_to_streaming_services::Migration),
            Box::new(m20260529_000001_create_provider_canonical_music_schema::Migration),
            Box::new(m20260529_000002_create_favourite_tracks_table::Migration),
        ]
    }
}
