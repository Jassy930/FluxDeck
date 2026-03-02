use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Gateway {
    pub id: String,
    pub name: String,
    pub listen_host: String,
    pub listen_port: i64,
    pub inbound_protocol: String,
    pub default_provider_id: String,
    pub default_model: Option<String>,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGatewayInput {
    pub id: String,
    pub name: String,
    pub listen_host: String,
    pub listen_port: i64,
    pub inbound_protocol: String,
    pub default_provider_id: String,
    pub default_model: Option<String>,
    pub enabled: bool,
}
