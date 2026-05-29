use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(FavouriteTracks::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(FavouriteTracks::Id)
                            .uuid()
                            .not_null()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(FavouriteTracks::UserId).uuid().not_null())
                    .col(ColumnDef::new(FavouriteTracks::UserTrackId).uuid().not_null())
                    .col(ColumnDef::new(FavouriteTracks::Source).string().not_null())
                    .col(ColumnDef::new(FavouriteTracks::ProviderTrackId).string().not_null())
                    .col(ColumnDef::new(FavouriteTracks::Title).string().not_null())
                    .col(ColumnDef::new(FavouriteTracks::Artist).string().not_null())
                    .col(ColumnDef::new(FavouriteTracks::AlbumName).string().null())
                    .col(ColumnDef::new(FavouriteTracks::Duration).integer().null())
                    .col(ColumnDef::new(FavouriteTracks::CoverUrl).string().null())
                    .col(ColumnDef::new(FavouriteTracks::CreatedAt).timestamp().not_null())
                    .col(ColumnDef::new(FavouriteTracks::UpdatedAt).timestamp().not_null())
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_favourite_tracks_user_id")
                            .from(FavouriteTracks::Table, FavouriteTracks::UserId)
                            .to(Users::Table, Users::Id)
                            .on_delete(ForeignKeyAction::Cascade),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_favourite_tracks_user_track_id")
                            .from(FavouriteTracks::Table, FavouriteTracks::UserTrackId)
                            .to(UserTracks::Table, UserTracks::Id)
                            .on_delete(ForeignKeyAction::Cascade),
                    )
                    .index(
                        Index::create()
                            .name("idx_favourite_tracks_user_track_unique")
                            .col(FavouriteTracks::UserId)
                            .col(FavouriteTracks::UserTrackId)
                            .unique(),
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_favourite_tracks_user_id")
                    .table(FavouriteTracks::Table)
                    .col(FavouriteTracks::UserId)
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_favourite_tracks_user_track_id")
                    .table(FavouriteTracks::Table)
                    .col(FavouriteTracks::UserTrackId)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(FavouriteTracks::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum FavouriteTracks {
    Table,
    Id,
    UserId,
    UserTrackId,
    Source,
    ProviderTrackId,
    Title,
    Artist,
    AlbumName,
    Duration,
    CoverUrl,
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