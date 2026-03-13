use anyhow::Result;
use sqlx::{Row, SqlitePool};

use crate::domain::gateway::GatewayRouteTarget;

#[derive(Clone)]
pub struct GatewayRouteRepo {
    pool: SqlitePool,
}

impl GatewayRouteRepo {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn list_by_gateway(&self, gateway_id: &str) -> Result<Vec<GatewayRouteTarget>> {
        let rows = sqlx::query(
            r#"
            SELECT id, gateway_id, provider_id, priority, enabled
            FROM gateway_route_targets
            WHERE gateway_id = ?1
            ORDER BY priority ASC, created_at ASC
            "#,
        )
        .bind(gateway_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| GatewayRouteTarget {
                id: row.get("id"),
                gateway_id: row.get("gateway_id"),
                provider_id: row.get("provider_id"),
                priority: row.get("priority"),
                enabled: row.get::<i64, _>("enabled") != 0,
            })
            .collect())
    }

    pub async fn list_gateway_ids_referencing_provider(
        &self,
        provider_id: &str,
    ) -> Result<Vec<String>> {
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT gateway_id
            FROM gateway_route_targets
            WHERE provider_id = ?1
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
}
