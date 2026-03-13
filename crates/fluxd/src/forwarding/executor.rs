use anyhow::{anyhow, Result};
use reqwest::StatusCode;
use serde_json::Value;
use sqlx::SqlitePool;

use crate::forwarding::route_selector::RouteSelector;
use crate::forwarding::target_resolver::ResolvedTarget;
use crate::service::provider_health_service::ProviderHealthService;
use crate::upstream::anthropic_client::AnthropicClient;
use crate::upstream::openai_client::OpenAiClient;

#[derive(Debug, Clone)]
pub struct RouteAttemptTrace {
    pub provider_id_initial: Option<String>,
    pub route_attempt_count: usize,
}

impl RouteAttemptTrace {
    fn for_attempts(targets: &[ResolvedTarget], route_attempt_count: usize) -> Self {
        Self {
            provider_id_initial: targets.first().map(|target| target.provider_id.clone()),
            route_attempt_count,
        }
    }
}

pub async fn execute_openai_json(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &OpenAiClient,
    payload: &Value,
) -> Result<(ResolvedTarget, StatusCode, Value, RouteAttemptTrace)> {
    let targets = RouteSelector::new(pool.clone())
        .ordered_candidates(gateway_id)
        .await?;
    let health_service = ProviderHealthService::new(pool.clone());
    let mut last_request_error = None;

    for (index, target) in targets.iter().enumerate() {
        match client
            .chat_completions(&target.base_url, &target.api_key, payload)
            .await
        {
            Ok((status, body)) => {
                if should_failover_status(status) && index + 1 < targets.len() {
                    let _ = health_service
                        .record_failure(&target.provider_id, &format!("status {}", status.as_u16()))
                        .await;
                    continue;
                }

                if status.is_success() {
                    let _ = health_service.record_success(&target.provider_id).await;
                } else if should_failover_status(status) {
                    let _ = health_service
                        .record_failure(&target.provider_id, &format!("status {}", status.as_u16()))
                        .await;
                }

                return Ok((
                    target.clone(),
                    status,
                    body,
                    RouteAttemptTrace::for_attempts(&targets, index + 1),
                ));
            }
            Err(err) => {
                let message = err.to_string();
                let _ = health_service
                    .record_failure(&target.provider_id, &message)
                    .await;
                if index + 1 < targets.len() {
                    last_request_error = Some(anyhow!(message));
                    continue;
                }
                return Err(anyhow!(message));
            }
        }
    }

    Err(last_request_error.unwrap_or_else(|| anyhow!("no available openai route targets")))
}

pub async fn execute_openai_stream(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &OpenAiClient,
    payload: &Value,
) -> Result<(
    ResolvedTarget,
    StatusCode,
    reqwest::Response,
    RouteAttemptTrace,
)> {
    let targets = RouteSelector::new(pool.clone())
        .ordered_candidates(gateway_id)
        .await?;
    let health_service = ProviderHealthService::new(pool.clone());
    let mut last_request_error = None;

    for (index, target) in targets.iter().enumerate() {
        match client
            .chat_completions_stream(&target.base_url, &target.api_key, payload)
            .await
        {
            Ok((status, response)) => {
                if should_failover_status(status) && index + 1 < targets.len() {
                    let _ = health_service
                        .record_failure(&target.provider_id, &format!("status {}", status.as_u16()))
                        .await;
                    continue;
                }

                if status.is_success() {
                    let _ = health_service.record_success(&target.provider_id).await;
                } else if should_failover_status(status) {
                    let _ = health_service
                        .record_failure(&target.provider_id, &format!("status {}", status.as_u16()))
                        .await;
                }

                return Ok((
                    target.clone(),
                    status,
                    response,
                    RouteAttemptTrace::for_attempts(&targets, index + 1),
                ));
            }
            Err(err) => {
                let message = err.to_string();
                let _ = health_service
                    .record_failure(&target.provider_id, &message)
                    .await;
                if index + 1 < targets.len() {
                    last_request_error = Some(anyhow!(message));
                    continue;
                }
                return Err(anyhow!(message));
            }
        }
    }

    Err(last_request_error.unwrap_or_else(|| anyhow!("no available openai stream route targets")))
}

pub async fn execute_anthropic_json(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &AnthropicClient,
    payload: &Value,
) -> Result<(ResolvedTarget, StatusCode, Value)> {
    let targets = RouteSelector::new(pool.clone())
        .ordered_candidates(gateway_id)
        .await?;
    let health_service = ProviderHealthService::new(pool.clone());
    let mut last_request_error = None;

    for (index, target) in targets.iter().enumerate() {
        match client
            .messages(&target.base_url, &target.api_key, payload)
            .await
        {
            Ok((status, body)) => {
                if should_failover_status(status) && index + 1 < targets.len() {
                    let _ = health_service
                        .record_failure(&target.provider_id, &format!("status {}", status.as_u16()))
                        .await;
                    continue;
                }

                if status.is_success() {
                    let _ = health_service.record_success(&target.provider_id).await;
                } else if should_failover_status(status) {
                    let _ = health_service
                        .record_failure(&target.provider_id, &format!("status {}", status.as_u16()))
                        .await;
                }

                return Ok((target.clone(), status, body));
            }
            Err(err) => {
                let message = err.to_string();
                let _ = health_service
                    .record_failure(&target.provider_id, &message)
                    .await;
                if index + 1 < targets.len() {
                    last_request_error = Some(anyhow!(message));
                    continue;
                }
                return Err(anyhow!(message));
            }
        }
    }

    Err(last_request_error.unwrap_or_else(|| anyhow!("no available anthropic route targets")))
}

pub async fn execute_anthropic_stream(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &AnthropicClient,
    payload: &Value,
) -> Result<(ResolvedTarget, StatusCode, reqwest::Response)> {
    let targets = RouteSelector::new(pool.clone())
        .ordered_candidates(gateway_id)
        .await?;
    let health_service = ProviderHealthService::new(pool.clone());
    let mut last_request_error = None;

    for (index, target) in targets.iter().enumerate() {
        match client
            .messages_stream(&target.base_url, &target.api_key, payload)
            .await
        {
            Ok((status, response)) => {
                if should_failover_status(status) && index + 1 < targets.len() {
                    let _ = health_service
                        .record_failure(&target.provider_id, &format!("status {}", status.as_u16()))
                        .await;
                    continue;
                }

                if status.is_success() {
                    let _ = health_service.record_success(&target.provider_id).await;
                } else if should_failover_status(status) {
                    let _ = health_service
                        .record_failure(&target.provider_id, &format!("status {}", status.as_u16()))
                        .await;
                }

                return Ok((target.clone(), status, response));
            }
            Err(err) => {
                let message = err.to_string();
                let _ = health_service
                    .record_failure(&target.provider_id, &message)
                    .await;
                if index + 1 < targets.len() {
                    last_request_error = Some(anyhow!(message));
                    continue;
                }
                return Err(anyhow!(message));
            }
        }
    }

    Err(last_request_error
        .unwrap_or_else(|| anyhow!("no available anthropic stream route targets")))
}

pub async fn execute_anthropic_count_tokens(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &AnthropicClient,
    payload: &Value,
) -> Result<(ResolvedTarget, StatusCode, Option<Value>)> {
    let target = RouteSelector::new(pool.clone()).select(gateway_id).await?;
    let (status, body) = client
        .messages_count_tokens(&target.base_url, &target.api_key, payload)
        .await?;
    Ok((target, status, body))
}

fn should_failover_status(status: StatusCode) -> bool {
    status.as_u16() == 429 || status.is_server_error()
}
