use anyhow::Result;
use reqwest::StatusCode;
use serde_json::Value;

#[derive(Clone)]
pub struct AnthropicClient {
    http: reqwest::Client,
}

impl AnthropicClient {
    pub fn new() -> Self {
        Self {
            http: reqwest::Client::new(),
        }
    }

    pub async fn messages(
        &self,
        base_url: &str,
        api_key: &str,
        payload: &Value,
    ) -> Result<(StatusCode, Value)> {
        let url = format!("{}/messages", base_url.trim_end_matches('/'));

        let response = self
            .http
            .post(url)
            .header("x-api-key", api_key)
            .header("anthropic-version", "2023-06-01")
            .json(payload)
            .send()
            .await?;

        let status = response.status();
        let body: Value = response.json().await?;

        Ok((status, body))
    }

    pub async fn messages_stream(
        &self,
        base_url: &str,
        api_key: &str,
        payload: &Value,
    ) -> Result<(StatusCode, reqwest::Response)> {
        let url = format!("{}/messages", base_url.trim_end_matches('/'));

        let response = self
            .http
            .post(url)
            .header("x-api-key", api_key)
            .header("anthropic-version", "2023-06-01")
            .json(payload)
            .send()
            .await?;

        let status = response.status();
        Ok((status, response))
    }

    pub async fn messages_count_tokens(
        &self,
        base_url: &str,
        api_key: &str,
        payload: &Value,
    ) -> Result<(StatusCode, Option<Value>)> {
        let url = format!("{}/messages/count_tokens", base_url.trim_end_matches('/'));

        let response = self
            .http
            .post(url)
            .header("x-api-key", api_key)
            .header("anthropic-version", "2023-06-01")
            .json(payload)
            .send()
            .await?;

        let status = response.status();
        let body = response.bytes().await?;
        let parsed = if body.is_empty() {
            None
        } else {
            serde_json::from_slice::<Value>(&body).ok()
        };

        Ok((status, parsed))
    }
}
