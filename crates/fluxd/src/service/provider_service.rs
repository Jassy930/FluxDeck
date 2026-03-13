use anyhow::Result;
use sqlx::SqlitePool;

use crate::domain::provider::{
    validate_provider_kind, CreateProviderInput, Provider, UpdateProviderInput,
};
use crate::repo::provider_health_repo::ProviderHealthRepo;
use crate::repo::provider_repo::ProviderRepo;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeleteProviderResult {
    Deleted,
    NotFound,
    ReferencedByGateways(Vec<String>),
}

#[derive(Clone)]
pub struct ProviderService {
    repo: ProviderRepo,
    health_repo: ProviderHealthRepo,
}

impl ProviderService {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            repo: ProviderRepo::new(pool.clone()),
            health_repo: ProviderHealthRepo::new(pool),
        }
    }

    pub async fn create_provider(&self, input: CreateProviderInput) -> Result<Provider> {
        validate_provider_kind(&input.kind)?;
        let provider = self.repo.create(input).await?;
        self.health_repo.ensure_default(&provider.id).await?;
        Ok(provider)
    }

    pub async fn get_provider_by_id(&self, provider_id: &str) -> Result<Option<Provider>> {
        self.repo.get_by_id(provider_id).await
    }

    pub async fn list_providers(&self) -> Result<Vec<Provider>> {
        self.repo.list().await
    }

    pub async fn update_provider(
        &self,
        provider_id: &str,
        input: UpdateProviderInput,
    ) -> Result<Option<Provider>> {
        validate_provider_kind(&input.kind)?;
        self.repo.update(provider_id, input).await
    }

    pub async fn delete_provider(&self, provider_id: &str) -> Result<DeleteProviderResult> {
        let Some(_) = self.repo.get_by_id(provider_id).await? else {
            return Ok(DeleteProviderResult::NotFound);
        };

        let referenced_by_gateway_ids = self.repo.list_gateway_ids_referencing(provider_id).await?;
        if !referenced_by_gateway_ids.is_empty() {
            return Ok(DeleteProviderResult::ReferencedByGateways(
                referenced_by_gateway_ids,
            ));
        }

        self.health_repo.delete_by_provider_id(provider_id).await?;
        let deleted = self.repo.delete(provider_id).await?;
        if deleted {
            Ok(DeleteProviderResult::Deleted)
        } else {
            Ok(DeleteProviderResult::NotFound)
        }
    }
}
