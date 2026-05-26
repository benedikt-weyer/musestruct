use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // Create the table
        manager
            .create_table(
                Table::create()
                    .table(SavedAlbum::Table)
                    .if_not_exists()
                    .col(uuid(SavedAlbum::Id).primary_key())
                    .col(uuid(SavedAlbum::UserId))
                    .col(string(SavedAlbum::AlbumId))
                    .col(string(SavedAlbum::Title))
                    .col(string(SavedAlbum::Artist))
                    .col(string_null(SavedAlbum::ReleaseDate))
                    .col(string_null(SavedAlbum::CoverUrl))
                    .col(string(SavedAlbum::Source))
                    .col(integer(SavedAlbum::TrackCount))
                    .col(timestamp(SavedAlbum::CreatedAt))
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_saved_albums_user_id")
                            .from(SavedAlbum::Table, SavedAlbum::UserId)
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
                    .name("idx_saved_albums_user_id")
                    .table(SavedAlbum::Table)
                    .col(SavedAlbum::UserId)
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_saved_albums_user_album_source")
                    .table(SavedAlbum::Table)
                    .col(SavedAlbum::UserId)
                    .col(SavedAlbum::AlbumId)
                    .col(SavedAlbum::Source)
                    .unique()
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(SavedAlbum::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum SavedAlbum {
    Table,
    Id,
    UserId,
    AlbumId,
    Title,
    Artist,
    ReleaseDate,
    CoverUrl,
    Source,
    TrackCount,
    CreatedAt,
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
}
