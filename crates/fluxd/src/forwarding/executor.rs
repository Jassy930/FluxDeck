use anyhow::Result;
use reqwest::StatusCode;
use serde_json::Value;
use sqlx::SqlitePool;

use crate::forwarding::target_resolver::{ResolvedTarget, TargetResolver};
use crate::upstream::anthropic_client::AnthropicClient;
use crate::upstream::openai_client::OpenAiClient;

pub async fn execute_openai_json(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &OpenAiClient,
    payload: &Value,
) -> Result<(ResolvedTarget, StatusCode, Value)> {
    let target = TargetResolver::new(pool.clone()).resolve(gateway_id).await?;
    let (status, body) = client
        .chat_completions(&target.base_url, &target.api_key, payload)
        .await?;
    Ok((target, status, body))
}

pub async fn execute_openai_stream(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &OpenAiClient,
    payload: &Value,
) -> Result<(ResolvedTarget, StatusCode, reqwest::Response)> {
    let target = TargetResolver::new(pool.clone()).resolve(gateway_id).await?;
    let (status, response) = client
        .chat_completions_stream(&target.base_url, &target.api_key, payload)
        .await?;
    Ok((target, status, response))
}

pub async fn execute_anthropic_json(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &AnthropicClient,
    payload: &Value,
) -> Result<(ResolvedTarget, StatusCode, Value)> {
    let target = TargetResolver::new(pool.clone()).resolve(gateway_id).await?;
    let (status, body) = client.messages(&target.base_url, &target.api_key, payload).await?;
    Ok((target, status, body))
}

pub async fn execute_anthropic_stream(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &AnthropicClient,
    payload: &Value,
) -> Result<(ResolvedTarget, StatusCode, reqwest::Response)> {
    let target = TargetResolver::new(pool.clone()).resolve(gateway_id).await?;
    let (status, response) = client
        .messages_stream(&target.base_url, &target.api_key, payload)
        .await?;
    Ok((target, status, response))
}

pub async fn execute_anthropic_count_tokens(
    pool: &SqlitePool,
    gateway_id: &str,
    client: &AnthropicClient,
    payload: &Value,
) -> Result<(ResolvedTarget, StatusCode, Option<Value>)> {
    let target = TargetResolver::new(pool.clone()).resolve(gateway_id).await?;
    let (status, body) = client
        .messages_count_tokens(&target.base_url, &target.api_key, payload)
        .await?;
    Ok((target, status, body))
}
