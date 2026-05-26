use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Songs::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Songs::Id)
                            .uuid()
                            .not_null()
                            .primary_key()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("uuid_generate_v4"))))
                    )
                    .col(ColumnDef::new(Songs::Title).string().not_null())
                    .col(ColumnDef::new(Songs::Artist).string().not_null())
                    .col(ColumnDef::new(Songs::AlbumId).uuid())
                    .col(ColumnDef::new(Songs::Duration).integer())
                    .col(ColumnDef::new(Songs::TrackNumber).integer())
                    .col(ColumnDef::new(Songs::ExternalId).string())
                    .col(ColumnDef::new(Songs::StreamUrl).text())
                    .col(ColumnDef::new(Songs::LocalPath).text())
                    .col(ColumnDef::new(Songs::Source).string().not_null().default("local"))
                    .col(ColumnDef::new(Songs::Quality).string())
                        .col(
                            ColumnDef::new(Songs::CreatedAt)
                                .timestamp()
                                .not_null()
                                .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                        )
                        .col(
                            ColumnDef::new(Songs::UpdatedAt)
                                .timestamp()
                            .not_null()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_songs_album_id")
                            .from(Songs::Table, Songs::AlbumId)
                            .to(Albums::Table, Albums::Id)
                            .on_delete(ForeignKeyAction::SetNull)
                    )
                    .to_owned(),
            )
            .await?;

        // Create indexes
        manager
            .create_index(
                Index::create()
                    .name("idx_songs_album_id")
                    .table(Songs::Table)
                    .col(Songs::AlbumId)
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_songs_source")
                    .table(Songs::Table)
                    .col(Songs::Source)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Songs::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum Songs {
    Table,
    Id,
    Title,
    Artist,
    AlbumId,
    Duration,
    TrackNumber,
    ExternalId,
    StreamUrl,
    LocalPath,
    Source,
    Quality,
    CreatedAt,
    UpdatedAt,
}

#[derive(DeriveIden)]
enum Albums {
    Table,
    Id,
}
