use anyhow::{anyhow, Result};
use serde_json::json;
use sqlx::{Row, SqlitePool};

use crate::forwarding::target_resolver::ResolvedTarget;

#[derive(Clone)]
pub struct RouteSelector {
    pool: SqlitePool,
}

impl RouteSelector {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn select(&self, gateway_id: &str) -> Result<ResolvedTarget> {
        self.ordered_candidates(gateway_id)
            .await?
            .into_iter()
            .next()
            .ok_or_else(|| anyhow!("gateway has no available route targets: {gateway_id}"))
    }

    pub async fn ordered_candidates(&self, gateway_id: &str) -> Result<Vec<ResolvedTarget>> {
        let rows = sqlx::query(
            r#"
            WITH configured_targets AS (
                SELECT gateway_id, provider_id, priority, enabled
                FROM gateway_route_targets
                WHERE gateway_id = ?1

                UNION ALL

                SELECT g.id AS gateway_id, g.default_provider_id AS provider_id, 0 AS priority, 1 AS enabled
                FROM gateways g
                WHERE g.id = ?1
                  AND NOT EXISTS (
                      SELECT 1
                      FROM gateway_route_targets rt
                      WHERE rt.gateway_id = g.id
                        AND rt.priority = 0
                  )
            )
            SELECT
                p.id AS provider_id,
                p.kind AS provider_kind,
                p.base_url,
                p.api_key,
                g.upstream_protocol,
                g.protocol_config_json,
                g.default_model,
                rt.priority,
                COALESCE(scoped.status, global.status, 'healthy') AS health_status
            FROM gateways g
            JOIN configured_targets rt ON rt.gateway_id = g.id
            JOIN providers p ON p.id = rt.provider_id
            LEFT JOIN provider_health_states scoped
              ON scoped.provider_id = p.id
             AND scoped.scope <> 'global'
             AND scoped.gateway_id = g.id
             AND scoped.model = ''
            LEFT JOIN provider_health_states global
              ON global.provider_id = p.id
             AND global.scope = 'global'
             AND global.gateway_id = ''
             AND global.model = ''
            WHERE g.id = ?1
              AND rt.enabled = 1
              AND p.enabled = 1
            ORDER BY rt.priority ASC, p.created_at ASC
            "#,
        )
        .bind(gateway_id)
        .fetch_all(&self.pool)
        .await?;

        if rows.is_empty() {
            return Err(anyhow!(
                "gateway not found or has no route targets: {gateway_id}"
            ));
        }

        let mut available = Vec::new();
        for row in rows {
            let health_status = row.get::<String, _>("health_status");
            if health_status == "unhealthy" {
                continue;
            }

            let configured_protocol = row.get::<String, _>("upstream_protocol");
            let provider_kind = row.get::<String, _>("provider_kind");
            let upstream_protocol = if configured_protocol == "provider_default" {
                provider_kind
            } else {
                configured_protocol
            };
            let protocol_config =
                serde_json::from_str(&row.get::<String, _>("protocol_config_json"))
                    .unwrap_or_else(|_| json!({}));

            available.push((
                health_rank(&health_status),
                row.get::<i64, _>("priority"),
                ResolvedTarget {
                    provider_id: row.get("provider_id"),
                    upstream_protocol,
                    base_url: row.get("base_url"),
                    api_key: row.get("api_key"),
                    effective_model: row.get("default_model"),
                    protocol_config,
                },
            ));
        }

        if available.is_empty() {
            return Err(anyhow!(
                "gateway has no healthy route targets available: {gateway_id}"
            ));
        }

        available.sort_by(|left, right| left.0.cmp(&right.0).then(left.1.cmp(&right.1)));
        Ok(available
            .into_iter()
            .map(|(_, _, target)| target)
            .collect())
    }
}

fn health_rank(status: &str) -> i32 {
    match status {
        "healthy" => 0,
        "probing" => 1,
        "degraded" => 2,
        "unhealthy" => 3,
        _ => 0,
    }
}
