use anyhow::Result;
use reqwest::StatusCode;
use serde_json::Value;

#[derive(Clone)]
pub struct OpenAiClient {
    http: reqwest::Client,
}

impl OpenAiClient {
    pub fn new() -> Self {
        Self {
            http: reqwest::Client::new(),
        }
    }

    pub async fn chat_completions(
        &self,
        base_url: &str,
        api_key: &str,
        payload: &Value,
    ) -> Result<(StatusCode, Value)> {
        let url = format!("{}/chat/completions", base_url.trim_end_matches('/'));

        let response = self
            .http
            .post(url)
            .bearer_auth(api_key)
            .json(payload)
            .send()
            .await?;

        let status = response.status();
        let body: Value = response.json().await?;

        Ok((status, body))
    }
}
