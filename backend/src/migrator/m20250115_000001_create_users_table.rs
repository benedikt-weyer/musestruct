use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // Create UUID extension first
        manager
            .get_connection()
            .execute_unprepared("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";")
            .await?;

        manager
            .create_table(
                Table::create()
                    .table(Users::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Users::Id)
                            .uuid()
                            .not_null()
                            .primary_key()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("uuid_generate_v4"))))
                    )
                    .col(ColumnDef::new(Users::Email).string().not_null().unique_key())
                    .col(ColumnDef::new(Users::Username).string().not_null())
                    .col(ColumnDef::new(Users::PasswordHash).string().not_null())
                        .col(
                            ColumnDef::new(Users::CreatedAt)
                                .timestamp()
                                .not_null()
                                .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                        )
                        .col(
                            ColumnDef::new(Users::UpdatedAt)
                                .timestamp()
                                .not_null()
                                .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                        )
                    .col(ColumnDef::new(Users::IsActive).boolean().not_null().default(true))
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Users::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
    Email,
    Username,
    PasswordHash,
    CreatedAt,
    UpdatedAt,
    IsActive,
}
