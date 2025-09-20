use sea_orm_migration::prelude::*;

mod m20250115_000001_create_users_table;
mod m20250115_000002_create_user_sessions_table;
mod m20250115_000003_create_albums_table;
mod m20250115_000004_create_songs_table;
mod m20250115_000005_create_playlists_table;
mod m20250115_000006_create_playlist_songs_table;
mod m20250115_000007_create_user_streaming_services_table;
mod m20250920_124747_add_account_username_to_streaming_services;
mod m20250920_155644_create_saved_tracks_table;
mod m20250920_161656_fix_saved_tracks_id_column;
mod m20250920_200000_create_queue_items_table;

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(m20250115_000001_create_users_table::Migration),
            Box::new(m20250115_000002_create_user_sessions_table::Migration),
            Box::new(m20250115_000003_create_albums_table::Migration),
            Box::new(m20250115_000004_create_songs_table::Migration),
            Box::new(m20250115_000005_create_playlists_table::Migration),
            Box::new(m20250115_000006_create_playlist_songs_table::Migration),
            Box::new(m20250115_000007_create_user_streaming_services_table::Migration),
            Box::new(m20250920_124747_add_account_username_to_streaming_services::Migration),
            Box::new(m20250920_155644_create_saved_tracks_table::Migration),
            Box::new(m20250920_161656_fix_saved_tracks_id_column::Migration),
            Box::new(m20250920_200000_create_queue_items_table::Migration),
        ]
    }
}
