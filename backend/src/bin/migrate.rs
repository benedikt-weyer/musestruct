use sea_orm_migration::prelude::*;
use dotenvy::dotenv;

mod migrator {
    pub use musestruct_backend::migrator::*;
}

use migrator::Migrator;

#[tokio::main]
async fn main() {
    dotenv().ok();

    cli::run_cli(Migrator).await;
}
