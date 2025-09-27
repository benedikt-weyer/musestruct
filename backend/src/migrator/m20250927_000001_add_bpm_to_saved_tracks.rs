use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .alter_table(
                Table::alter()
                    .table(SavedTrack::Table)
                    .add_column(float_null(SavedTrack::Bpm))
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .alter_table(
                Table::alter()
                    .table(SavedTrack::Table)
                    .drop_column(SavedTrack::Bpm)
                    .to_owned(),
            )
            .await
    }
}

#[derive(DeriveIden)]
enum SavedTrack {
    Table,
    Bpm,
}
