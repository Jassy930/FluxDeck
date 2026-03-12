use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::domain::provider::SUPPORTED_PROVIDER_KINDS;

pub const PROVIDER_DEFAULT_UPSTREAM_PROTOCOL: &str = "provider_default";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Gateway {
    pub id: String,
    pub name: String,
    pub listen_host: String,
    pub listen_port: i64,
    pub inbound_protocol: String,
    pub upstream_protocol: String,
    pub protocol_config_json: Value,
    pub default_provider_id: String,
    pub default_model: Option<String>,
    pub enabled: bool,
    pub auto_start: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGatewayInput {
    pub id: String,
    pub name: String,
    pub listen_host: String,
    pub listen_port: i64,
    pub inbound_protocol: String,
    #[serde(default = "default_upstream_protocol")]
    pub upstream_protocol: String,
    #[serde(default = "default_protocol_config_json")]
    pub protocol_config_json: Value,
    pub default_provider_id: String,
    pub default_model: Option<String>,
    pub enabled: bool,
    #[serde(default)]
    pub auto_start: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateGatewayInput {
    pub name: String,
    pub listen_host: String,
    pub listen_port: i64,
    pub inbound_protocol: String,
    #[serde(default = "default_upstream_protocol")]
    pub upstream_protocol: String,
    #[serde(default = "default_protocol_config_json")]
    pub protocol_config_json: Value,
    pub default_provider_id: String,
    pub default_model: Option<String>,
    pub enabled: bool,
    #[serde(default)]
    pub auto_start: bool,
}

fn default_upstream_protocol() -> String {
    PROVIDER_DEFAULT_UPSTREAM_PROTOCOL.to_string()
}

fn default_protocol_config_json() -> Value {
    Value::Object(Default::default())
}

pub fn is_supported_gateway_inbound_protocol(protocol: &str) -> bool {
    SUPPORTED_PROVIDER_KINDS.contains(&protocol)
}

pub fn is_supported_gateway_upstream_protocol(protocol: &str) -> bool {
    protocol == PROVIDER_DEFAULT_UPSTREAM_PROTOCOL
        || is_supported_gateway_inbound_protocol(protocol)
}

pub fn validate_gateway_inbound_protocol(protocol: &str) -> Result<()> {
    if is_supported_gateway_inbound_protocol(protocol) {
        return Ok(());
    }

    Err(anyhow!(
        "unsupported inbound protocol `{protocol}`; supported protocols: {}",
        SUPPORTED_PROVIDER_KINDS.join(", ")
    ))
}

pub fn validate_gateway_upstream_protocol(protocol: &str) -> Result<()> {
    if is_supported_gateway_upstream_protocol(protocol) {
        return Ok(());
    }

    Err(anyhow!(
        "unsupported upstream protocol `{protocol}`; supported protocols: {}, {}",
        PROVIDER_DEFAULT_UPSTREAM_PROTOCOL,
        SUPPORTED_PROVIDER_KINDS.join(", ")
    ))
}
