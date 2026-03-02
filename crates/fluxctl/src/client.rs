use anyhow::Result;
use serde_json::Value;

#[derive(Clone)]
pub struct AdminClient {
    base_url: String,
    http: reqwest::Client,
}

impl AdminClient {
    pub fn new(base_url: impl Into<String>) -> Self {
        Self {
            base_url: base_url.into(),
            http: reqwest::Client::new(),
        }
    }

    pub async fn post_json(&self, path: &str, payload: Value) -> Result<Value> {
        let url = format!("{}{}", self.base_url.trim_end_matches('/'), path);
        let resp = self.http.post(url).json(&payload).send().await?;
        let body = resp.json::<Value>().await?;
        Ok(body)
    }

    pub async fn get_json(&self, path: &str) -> Result<Value> {
        let url = format!("{}{}", self.base_url.trim_end_matches('/'), path);
        let resp = self.http.get(url).send().await?;
        let body = resp.json::<Value>().await?;
        Ok(body)
    }
}
