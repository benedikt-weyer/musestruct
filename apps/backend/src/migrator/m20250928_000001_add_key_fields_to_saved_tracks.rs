use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .alter_table(
                Table::alter()
                    .table(SavedTrack::Table)
                    .add_column(
                        ColumnDef::new(SavedTrack::KeyName)
                            .string()
                            .null()
                    )
                    .add_column(
                        ColumnDef::new(SavedTrack::Camelot)
                            .string()
                            .null()
                    )
                    .add_column(
                        ColumnDef::new(SavedTrack::KeyConfidence)
                            .float()
                            .null()
                    )
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .alter_table(
                Table::alter()
                    .table(SavedTrack::Table)
                    .drop_column(SavedTrack::KeyName)
                    .drop_column(SavedTrack::Camelot)
                    .drop_column(SavedTrack::KeyConfidence)
                    .to_owned(),
            )
            .await
    }
}

#[derive(DeriveIden)]
enum SavedTrack {
    Table,
    KeyName,
    Camelot,
    KeyConfidence,
}
