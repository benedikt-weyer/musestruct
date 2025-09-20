use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(QueueItems::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(QueueItems::Id)
                            .uuid()
                            .not_null()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(QueueItems::UserId).uuid().not_null())
                    .col(ColumnDef::new(QueueItems::TrackId).string().not_null())
                    .col(ColumnDef::new(QueueItems::Title).string().not_null())
                    .col(ColumnDef::new(QueueItems::Artist).string().not_null())
                    .col(ColumnDef::new(QueueItems::Album).string().not_null())
                    .col(ColumnDef::new(QueueItems::Duration).integer().not_null())
                    .col(ColumnDef::new(QueueItems::Source).string().not_null())
                    .col(ColumnDef::new(QueueItems::CoverUrl).string().null())
                    .col(ColumnDef::new(QueueItems::Position).integer().not_null())
                    .col(ColumnDef::new(QueueItems::AddedAt).timestamp().not_null())
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_queue_items_user_id")
                            .from(QueueItems::Table, QueueItems::UserId)
                            .to(Users::Table, Users::Id)
                            .on_delete(ForeignKeyAction::Cascade),
                    )
                    .to_owned(),
            )
            .await?;

        // Create index on user_id and position for efficient querying
        manager
            .create_index(
                Index::create()
                    .name("idx_queue_items_user_position")
                    .table(QueueItems::Table)
                    .col(QueueItems::UserId)
                    .col(QueueItems::Position)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(QueueItems::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum QueueItems {
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
    Position,
    AddedAt,
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
}
