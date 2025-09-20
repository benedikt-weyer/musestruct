use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // Drop the existing table with wrong schema
        manager
            .drop_table(Table::drop().table(SavedTrack::Table).to_owned())
            .await?;

        // Recreate the table with correct UUID primary key
        manager
            .create_table(
                Table::create()
                    .table(SavedTrack::Table)
                    .if_not_exists()
                    .col(uuid(SavedTrack::Id).primary_key())
                    .col(uuid(SavedTrack::UserId))
                    .col(string(SavedTrack::TrackId))
                    .col(string(SavedTrack::Title))
                    .col(string(SavedTrack::Artist))
                    .col(string(SavedTrack::Album))
                    .col(integer(SavedTrack::Duration))
                    .col(string(SavedTrack::Source))
                    .col(string_null(SavedTrack::CoverUrl))
                    .col(timestamp(SavedTrack::CreatedAt))
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_saved_tracks_user_id")
                            .from(SavedTrack::Table, SavedTrack::UserId)
                            .to(Users::Table, Users::Id)
                            .on_delete(ForeignKeyAction::Cascade)
                    )
                    .to_owned(),
            )
            .await?;

        // Create indexes
        manager
            .create_index(
                Index::create()
                    .name("idx_saved_tracks_user_id")
                    .table(SavedTrack::Table)
                    .col(SavedTrack::UserId)
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_saved_tracks_track_source")
                    .table(SavedTrack::Table)
                    .col(SavedTrack::TrackId)
                    .col(SavedTrack::Source)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // Drop indexes first
        manager
            .drop_index(
                Index::drop()
                    .name("idx_saved_tracks_track_source")
                    .to_owned(),
            )
            .await?;

        manager
            .drop_index(
                Index::drop()
                    .name("idx_saved_tracks_user_id")
                    .to_owned(),
            )
            .await?;

        // Drop the table
        manager
            .drop_table(Table::drop().table(SavedTrack::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum SavedTrack {
    Table,
    Id,
    UserId,
    TrackId,
    Title,
    Artist,
    Album,
    Duration,
    Source,
    CoverUrl,
    CreatedAt,
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
}
