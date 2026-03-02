use anyhow::Result;
use sqlx::SqlitePool;

use crate::domain::provider::{CreateProviderInput, Provider};
use crate::repo::provider_repo::ProviderRepo;

#[derive(Clone)]
pub struct ProviderService {
    repo: ProviderRepo,
}

impl ProviderService {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            repo: ProviderRepo::new(pool),
        }
    }

    pub async fn create_provider(&self, input: CreateProviderInput) -> Result<Provider> {
        self.repo.create(input).await
    }

    pub async fn get_provider_by_id(&self, provider_id: &str) -> Result<Option<Provider>> {
        self.repo.get_by_id(provider_id).await
    }

    pub async fn list_providers(&self) -> Result<Vec<Provider>> {
        self.repo.list().await
    }
}
