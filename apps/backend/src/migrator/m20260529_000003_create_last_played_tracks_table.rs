use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(LastPlayedTracks::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(LastPlayedTracks::Id)
                            .uuid()
                            .not_null()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(LastPlayedTracks::UserId).uuid().not_null())
                    .col(ColumnDef::new(LastPlayedTracks::UserTrackId).uuid().not_null())
                    .col(ColumnDef::new(LastPlayedTracks::PlayedAt).timestamp().not_null())
                    .col(ColumnDef::new(LastPlayedTracks::CreatedAt).timestamp().not_null())
                    .col(ColumnDef::new(LastPlayedTracks::UpdatedAt).timestamp().not_null())
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_last_played_tracks_user_id")
                            .from(LastPlayedTracks::Table, LastPlayedTracks::UserId)
                            .to(Users::Table, Users::Id)
                            .on_delete(ForeignKeyAction::Cascade),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_last_played_tracks_user_track_id")
                            .from(LastPlayedTracks::Table, LastPlayedTracks::UserTrackId)
                            .to(UserTracks::Table, UserTracks::Id)
                            .on_delete(ForeignKeyAction::Cascade),
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_last_played_tracks_user_track_unique")
                    .table(LastPlayedTracks::Table)
                    .col(LastPlayedTracks::UserId)
                    .col(LastPlayedTracks::UserTrackId)
                    .unique()
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_last_played_tracks_user_played_at")
                    .table(LastPlayedTracks::Table)
                    .col(LastPlayedTracks::UserId)
                    .col(LastPlayedTracks::PlayedAt)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(LastPlayedTracks::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum LastPlayedTracks {
    Table,
    Id,
    UserId,
    UserTrackId,
    PlayedAt,
    CreatedAt,
    UpdatedAt,
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
}

#[derive(DeriveIden)]
enum UserTracks {
    Table,
    Id,
}