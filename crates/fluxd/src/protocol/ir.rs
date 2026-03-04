use std::collections::BTreeMap;

use serde_json::Value;

#[derive(Debug, Clone, PartialEq)]
pub struct ProtocolIrMessage {
    pub role: String,
    pub content: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProtocolIrRequest {
    pub source_protocol: String,
    pub target_protocol: String,
    pub model: Option<String>,
    pub messages: Vec<ProtocolIrMessage>,
    pub metadata: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProtocolIrResponse {
    pub target_protocol: String,
    pub output: Value,
    pub metadata: BTreeMap<String, Value>,
}
