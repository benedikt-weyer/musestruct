use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Playlists::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Playlists::Id)
                            .uuid()
                            .not_null()
                            .primary_key()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("uuid_generate_v4"))))
                    )
                    .col(ColumnDef::new(Playlists::Name).string().not_null())
                    .col(ColumnDef::new(Playlists::Description).text())
                    .col(ColumnDef::new(Playlists::UserId).uuid().not_null())
                    .col(ColumnDef::new(Playlists::IsPublic).boolean().not_null().default(false))
                        .col(
                            ColumnDef::new(Playlists::CreatedAt)
                                .timestamp()
                                .not_null()
                                .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                        )
                        .col(
                            ColumnDef::new(Playlists::UpdatedAt)
                                .timestamp()
                            .not_null()
                            .default(SimpleExpr::FunctionCall(Func::cust(Alias::new("NOW"))))
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_playlists_user_id")
                            .from(Playlists::Table, Playlists::UserId)
                            .to(Users::Table, Users::Id)
                            .on_delete(ForeignKeyAction::Cascade)
                    )
                    .to_owned(),
            )
            .await?;

        // Create index
        manager
            .create_index(
                Index::create()
                    .name("idx_playlists_user_id")
                    .table(Playlists::Table)
                    .col(Playlists::UserId)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Playlists::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum Playlists {
    Table,
    Id,
    Name,
    Description,
    UserId,
    IsPublic,
    CreatedAt,
    UpdatedAt,
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
}
