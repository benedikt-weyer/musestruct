use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .alter_table(
                Table::alter()
                    .table(UserStreamingServices::Table)
                    .add_column(ColumnDef::new(UserStreamingServices::AccountUsername).string())
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .alter_table(
                Table::alter()
                    .table(UserStreamingServices::Table)
                    .drop_column(UserStreamingServices::AccountUsername)
                    .to_owned(),
            )
            .await
    }
}

#[derive(DeriveIden)]
enum UserStreamingServices {
    Table,
    AccountUsername,
}
