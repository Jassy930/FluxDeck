use anyhow::Result;
use reqwest::StatusCode;
use serde_json::Value;

use crate::protocol::adapters::openai::encode_openai_chat_request;
use crate::protocol::ir::IrRequest;

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

    pub async fn chat_completions_stream(
        &self,
        base_url: &str,
        api_key: &str,
        payload: &Value,
    ) -> Result<(StatusCode, reqwest::Response)> {
        let url = format!("{}/chat/completions", base_url.trim_end_matches('/'));

        let response = self
            .http
            .post(url)
            .bearer_auth(api_key)
            .json(payload)
            .send()
            .await?;

        let status = response.status();
        Ok((status, response))
    }

    pub async fn anthropic_messages_count_tokens(
        &self,
        base_url: &str,
        api_key: &str,
        payload: &Value,
    ) -> Result<(StatusCode, Option<Value>)> {
        let url = format!("{}/messages/count_tokens", base_url.trim_end_matches('/'));

        let response = self
            .http
            .post(url)
            .bearer_auth(api_key)
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

    pub async fn chat_completions_from_ir(
        &self,
        base_url: &str,
        api_key: &str,
        ir: &IrRequest,
    ) -> Result<(StatusCode, Value)> {
        let payload = encode_openai_chat_request(ir)?;
        self.chat_completions(base_url, api_key, &payload).await
    }
}
