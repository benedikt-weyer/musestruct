use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .add_column(
                        ColumnDef::new(PlaylistItems::Title)
                            .string()
                            .null()
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .add_column(
                        ColumnDef::new(PlaylistItems::Artist)
                            .string()
                            .null()
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .add_column(
                        ColumnDef::new(PlaylistItems::Album)
                            .string()
                            .null()
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .add_column(
                        ColumnDef::new(PlaylistItems::Duration)
                            .integer()
                            .null()
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .add_column(
                        ColumnDef::new(PlaylistItems::Source)
                            .string()
                            .null()
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .add_column(
                        ColumnDef::new(PlaylistItems::CoverUrl)
                            .string()
                            .null()
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .add_column(
                        ColumnDef::new(PlaylistItems::PlaylistName)
                            .string()
                            .null()
                    )
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .drop_column(PlaylistItems::Title)
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .drop_column(PlaylistItems::Artist)
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .drop_column(PlaylistItems::Album)
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .drop_column(PlaylistItems::Duration)
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .drop_column(PlaylistItems::Source)
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .drop_column(PlaylistItems::CoverUrl)
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(PlaylistItems::Table)
                    .drop_column(PlaylistItems::PlaylistName)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }
}

#[derive(DeriveIden)]
enum PlaylistItems {
    Table,
    Title,
    Artist,
    Album,
    Duration,
    Source,
    CoverUrl,
    PlaylistName,
}
