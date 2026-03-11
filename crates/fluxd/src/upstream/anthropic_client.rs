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
        let url = anthropic_endpoint(base_url, "messages");

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
        let url = anthropic_endpoint(base_url, "messages");

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
        let url = anthropic_endpoint(base_url, "messages/count_tokens");

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

fn anthropic_endpoint(base_url: &str, path: &str) -> String {
    let normalized = base_url.trim_end_matches('/');
    let prefix = if normalized.ends_with("/v1") {
        normalized.to_string()
    } else {
        format!("{normalized}/v1")
    };

    format!("{prefix}/{path}")
}

#[cfg(test)]
mod tests {
    use super::anthropic_endpoint;

    #[test]
    fn appends_v1_when_base_url_omits_version() {
        assert_eq!(
            anthropic_endpoint("https://open.bigmodel.cn/api/anthropic", "messages"),
            "https://open.bigmodel.cn/api/anthropic/v1/messages"
        );
    }

    #[test]
    fn keeps_existing_v1_suffix() {
        assert_eq!(
            anthropic_endpoint("https://api.anthropic.com/v1/", "messages/count_tokens"),
            "https://api.anthropic.com/v1/messages/count_tokens"
        );
    }
}
