use serde::{Deserialize, Serialize};
use serde_json::Value;

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
    "provider_default".to_string()
}

fn default_protocol_config_json() -> Value {
    Value::Object(Default::default())
}
