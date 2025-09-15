use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(UserStreamingServices::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(UserStreamingServices::Id)
                            .uuid()
                            .not_null()
                            .primary_key()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("uuid_generate_v4"))))
                    )
                    .col(ColumnDef::new(UserStreamingServices::UserId).uuid().not_null())
                    .col(ColumnDef::new(UserStreamingServices::ServiceName).string().not_null())
                    .col(ColumnDef::new(UserStreamingServices::AccessToken).text())
                    .col(ColumnDef::new(UserStreamingServices::RefreshToken).text())
                    .col(ColumnDef::new(UserStreamingServices::ExpiresAt).timestamp_with_time_zone())
                    .col(ColumnDef::new(UserStreamingServices::IsActive).boolean().not_null().default(true))
                    .col(
                        ColumnDef::new(UserStreamingServices::CreatedAt)
                            .timestamp_with_time_zone()
                            .not_null()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                    )
                    .col(
                        ColumnDef::new(UserStreamingServices::UpdatedAt)
                            .timestamp_with_time_zone()
                            .not_null()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_user_streaming_services_user_id")
                            .from(UserStreamingServices::Table, UserStreamingServices::UserId)
                            .to(Users::Table, Users::Id)
                            .on_delete(ForeignKeyAction::Cascade)
                    )
                    .to_owned(),
            )
            .await?;

        // Create unique constraint
        manager
            .create_index(
                Index::create()
                    .name("idx_user_streaming_services_unique")
                    .table(UserStreamingServices::Table)
                    .col(UserStreamingServices::UserId)
                    .col(UserStreamingServices::ServiceName)
                    .unique()
                    .to_owned(),
            )
            .await?;

        // Create index
        manager
            .create_index(
                Index::create()
                    .name("idx_user_streaming_services_user_id")
                    .table(UserStreamingServices::Table)
                    .col(UserStreamingServices::UserId)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(UserStreamingServices::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum UserStreamingServices {
    Table,
    Id,
    UserId,
    ServiceName,
    AccessToken,
    RefreshToken,
    ExpiresAt,
    IsActive,
    CreatedAt,
    UpdatedAt,
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
}
