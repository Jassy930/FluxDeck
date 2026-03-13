use anyhow::Result;
use sqlx::{Row, SqlitePool};

use crate::domain::provider::{CreateProviderInput, Provider, UpdateProviderInput};

#[derive(Clone)]
pub struct ProviderRepo {
    pool: SqlitePool,
}

impl ProviderRepo {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn create(&self, input: CreateProviderInput) -> Result<Provider> {
        let mut tx = self.pool.begin().await?;

        sqlx::query(
            r#"
            INSERT INTO providers (id, name, kind, base_url, api_key, enabled)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            "#,
        )
        .bind(&input.id)
        .bind(&input.name)
        .bind(&input.kind)
        .bind(&input.base_url)
        .bind(&input.api_key)
        .bind(if input.enabled { 1_i64 } else { 0_i64 })
        .execute(&mut *tx)
        .await?;

        for model in &input.models {
            let model_id = format!("{}_{}", &input.id, model.replace('/', "_"));
            sqlx::query(
                r#"
                INSERT INTO provider_models (id, provider_id, model_name)
                VALUES (?1, ?2, ?3)
                "#,
            )
            .bind(model_id)
            .bind(&input.id)
            .bind(model)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;

        Ok(Provider {
            id: input.id,
            name: input.name,
            kind: input.kind,
            base_url: input.base_url,
            api_key: input.api_key,
            models: input.models,
            enabled: input.enabled,
        })
    }

    pub async fn get_by_id(&self, provider_id: &str) -> Result<Option<Provider>> {
        let row_opt = sqlx::query(
            r#"
            SELECT id, name, kind, base_url, api_key, enabled
            FROM providers
            WHERE id = ?1
            "#,
        )
        .bind(provider_id)
        .fetch_optional(&self.pool)
        .await?;

        let Some(row) = row_opt else {
            return Ok(None);
        };

        let models = self.list_models(provider_id).await?;

        Ok(Some(Provider {
            id: row.get("id"),
            name: row.get("name"),
            kind: row.get("kind"),
            base_url: row.get("base_url"),
            api_key: row.get("api_key"),
            models,
            enabled: row.get::<i64, _>("enabled") != 0,
        }))
    }

    pub async fn update(
        &self,
        provider_id: &str,
        input: UpdateProviderInput,
    ) -> Result<Option<Provider>> {
        let mut tx = self.pool.begin().await?;

        let result = sqlx::query(
            r#"
            UPDATE providers
            SET name = ?1, kind = ?2, base_url = ?3, api_key = ?4, enabled = ?5
            WHERE id = ?6
            "#,
        )
        .bind(&input.name)
        .bind(&input.kind)
        .bind(&input.base_url)
        .bind(&input.api_key)
        .bind(if input.enabled { 1_i64 } else { 0_i64 })
        .bind(provider_id)
        .execute(&mut *tx)
        .await?;

        if result.rows_affected() == 0 {
            return Ok(None);
        }

        sqlx::query("DELETE FROM provider_models WHERE provider_id = ?1")
            .bind(provider_id)
            .execute(&mut *tx)
            .await?;

        for model in &input.models {
            let model_id = format!("{}_{}", provider_id, model.replace('/', "_"));
            sqlx::query(
                r#"
                INSERT INTO provider_models (id, provider_id, model_name)
                VALUES (?1, ?2, ?3)
                "#,
            )
            .bind(model_id)
            .bind(provider_id)
            .bind(model)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;

        Ok(Some(Provider {
            id: provider_id.to_string(),
            name: input.name,
            kind: input.kind,
            base_url: input.base_url,
            api_key: input.api_key,
            models: input.models,
            enabled: input.enabled,
        }))
    }

    pub async fn list(&self) -> Result<Vec<Provider>> {
        let rows = sqlx::query(
            r#"
            SELECT id, name, kind, base_url, api_key, enabled
            FROM providers
            ORDER BY created_at DESC
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let mut providers = Vec::with_capacity(rows.len());
        for row in rows {
            let id: String = row.get("id");
            let models = self.list_models(&id).await?;

            providers.push(Provider {
                id,
                name: row.get("name"),
                kind: row.get("kind"),
                base_url: row.get("base_url"),
                api_key: row.get("api_key"),
                models,
                enabled: row.get::<i64, _>("enabled") != 0,
            });
        }

        Ok(providers)
    }

    pub async fn list_gateway_ids_referencing(&self, provider_id: &str) -> Result<Vec<String>> {
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT gateway_id
            FROM (
                SELECT id AS gateway_id
                FROM gateways
                WHERE default_provider_id = ?1

                UNION

                SELECT gateway_id
                FROM gateway_route_targets
                WHERE provider_id = ?1
            )
            ORDER BY gateway_id ASC
            "#,
        )
        .bind(provider_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| row.get::<String, _>("gateway_id"))
            .collect())
    }

    pub async fn delete(&self, provider_id: &str) -> Result<bool> {
        let mut tx = self.pool.begin().await?;

        sqlx::query("DELETE FROM provider_models WHERE provider_id = ?1")
            .bind(provider_id)
            .execute(&mut *tx)
            .await?;

        let result = sqlx::query("DELETE FROM providers WHERE id = ?1")
            .bind(provider_id)
            .execute(&mut *tx)
            .await?;

        tx.commit().await?;

        Ok(result.rows_affected() > 0)
    }

    async fn list_models(&self, provider_id: &str) -> Result<Vec<String>> {
        let rows = sqlx::query(
            r#"
            SELECT model_name
            FROM provider_models
            WHERE provider_id = ?1
            ORDER BY rowid ASC
            "#,
        )
        .bind(provider_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| row.get::<String, _>("model_name"))
            .collect())
    }
}
