use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // Create playlist_items table (playlists table already exists)
        manager
            .create_table(
                Table::create()
                    .table(PlaylistItems::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(PlaylistItems::Id)
                            .uuid()
                            .not_null()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(PlaylistItems::PlaylistId).uuid().not_null())
                    .col(ColumnDef::new(PlaylistItems::ItemType).string().not_null()) // "track" or "playlist"
                    .col(ColumnDef::new(PlaylistItems::ItemId).string().not_null()) // track_id or playlist_id
                    .col(ColumnDef::new(PlaylistItems::Position).integer().not_null())
                    .col(ColumnDef::new(PlaylistItems::AddedAt).timestamp().not_null())
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_playlist_items_playlist_id")
                            .from(PlaylistItems::Table, PlaylistItems::PlaylistId)
                            .to("playlists", "id")
                            .on_delete(ForeignKeyAction::Cascade),
                    )
                    .to_owned(),
            )
            .await?;

        // Create indexes for playlist_items
        manager
            .create_index(
                Index::create()
                    .name("idx_playlist_items_playlist_id")
                    .table(PlaylistItems::Table)
                    .col(PlaylistItems::PlaylistId)
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_playlist_items_position")
                    .table(PlaylistItems::Table)
                    .col(PlaylistItems::PlaylistId)
                    .col(PlaylistItems::Position)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(PlaylistItems::Table).to_owned())
            .await?;

        Ok(())
    }
}

#[derive(DeriveIden)]
enum PlaylistItems {
    Table,
    Id,
    PlaylistId,
    ItemType,
    ItemId,
    Position,
    AddedAt,
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
}
