use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(PlaylistSongs::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(PlaylistSongs::Id)
                            .uuid()
                            .not_null()
                            .primary_key()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("uuid_generate_v4"))))
                    )
                    .col(ColumnDef::new(PlaylistSongs::PlaylistId).uuid().not_null())
                    .col(ColumnDef::new(PlaylistSongs::SongId).uuid().not_null())
                    .col(ColumnDef::new(PlaylistSongs::Position).integer().not_null())
                    .col(
                        ColumnDef::new(PlaylistSongs::AddedAt)
                            .timestamp()
                            .not_null()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_playlist_songs_playlist_id")
                            .from(PlaylistSongs::Table, PlaylistSongs::PlaylistId)
                            .to(Playlists::Table, Playlists::Id)
                            .on_delete(ForeignKeyAction::Cascade)
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_playlist_songs_song_id")
                            .from(PlaylistSongs::Table, PlaylistSongs::SongId)
                            .to(Songs::Table, Songs::Id)
                            .on_delete(ForeignKeyAction::Cascade)
                    )
                    .to_owned(),
            )
            .await?;

        // Create unique constraint
        manager
            .create_index(
                Index::create()
                    .name("idx_playlist_songs_unique")
                    .table(PlaylistSongs::Table)
                    .col(PlaylistSongs::PlaylistId)
                    .col(PlaylistSongs::SongId)
                    .unique()
                    .to_owned(),
            )
            .await?;

        // Create indexes
        manager
            .create_index(
                Index::create()
                    .name("idx_playlist_songs_playlist_id")
                    .table(PlaylistSongs::Table)
                    .col(PlaylistSongs::PlaylistId)
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_playlist_songs_song_id")
                    .table(PlaylistSongs::Table)
                    .col(PlaylistSongs::SongId)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(PlaylistSongs::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum PlaylistSongs {
    Table,
    Id,
    PlaylistId,
    SongId,
    Position,
    AddedAt,
}

#[derive(DeriveIden)]
enum Playlists {
    Table,
    Id,
}

#[derive(DeriveIden)]
enum Songs {
    Table,
    Id,
}
