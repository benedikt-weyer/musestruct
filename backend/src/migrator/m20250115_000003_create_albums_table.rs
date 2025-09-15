use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Albums::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Albums::Id)
                            .uuid()
                            .not_null()
                            .primary_key()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("uuid_generate_v4"))))
                    )
                    .col(ColumnDef::new(Albums::Title).string().not_null())
                    .col(ColumnDef::new(Albums::Artist).string().not_null())
                    .col(ColumnDef::new(Albums::ReleaseDate).date())
                    .col(ColumnDef::new(Albums::CoverUrl).text())
                    .col(ColumnDef::new(Albums::ExternalId).string())
                    .col(ColumnDef::new(Albums::Source).string().not_null().default("local"))
                    .col(
                        ColumnDef::new(Albums::CreatedAt)
                            .timestamp_with_time_zone()
                            .not_null()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                    )
                    .col(
                        ColumnDef::new(Albums::UpdatedAt)
                            .timestamp_with_time_zone()
                            .not_null()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                    )
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Albums::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum Albums {
    Table,
    Id,
    Title,
    Artist,
    ReleaseDate,
    CoverUrl,
    ExternalId,
    Source,
    CreatedAt,
    UpdatedAt,
}
