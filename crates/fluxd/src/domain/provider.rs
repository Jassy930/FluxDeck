use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};

pub const SUPPORTED_PROVIDER_KINDS: &[&str] = &[
    "openai",
    "openai-response",
    "gemini",
    "anthropic",
    "azure-openai",
    "new-api",
    "ollama",
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Provider {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub base_url: String,
    pub api_key: String,
    pub models: Vec<String>,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateProviderInput {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub base_url: String,
    pub api_key: String,
    pub models: Vec<String>,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateProviderInput {
    pub name: String,
    pub kind: String,
    pub base_url: String,
    pub api_key: String,
    pub models: Vec<String>,
    pub enabled: bool,
}

pub fn is_supported_provider_kind(kind: &str) -> bool {
    SUPPORTED_PROVIDER_KINDS.contains(&kind)
}

pub fn validate_provider_kind(kind: &str) -> Result<()> {
    if is_supported_provider_kind(kind) {
        return Ok(());
    }

    Err(anyhow!(
        "unsupported provider kind `{kind}`; supported kinds: {}",
        SUPPORTED_PROVIDER_KINDS.join(", ")
    ))
}
