use std::collections::BTreeMap;

use serde_json::Value;

use crate::protocol::error::{DecodeErrorKind, FluxError};
use crate::protocol::ir::{IrRequest, ProtocolIrMessage};

pub fn decode_anthropic_request(payload: &Value) -> Result<IrRequest, FluxError> {
    let root = payload.as_object().ok_or_else(|| FluxError::DecodeError {
        protocol: "anthropic".to_string(),
        kind: DecodeErrorKind::InvalidPayload,
    })?;

    let model = root
        .get("model")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .ok_or_else(|| FluxError::DecodeError {
            protocol: "anthropic".to_string(),
            kind: DecodeErrorKind::MissingRequiredField {
                field: "model".to_string(),
            },
        })?;

    let system_parts = decode_system(root.get("system"));
    let messages = decode_messages(root.get("messages"));
    let tools = decode_tools(root.get("tools"));
    let extensions = collect_extensions(root);

    Ok(IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "ir".to_string(),
        model: Some(model),
        system_parts,
        messages,
        tools,
        extensions,
        metadata: BTreeMap::new(),
    })
}

fn decode_system(system: Option<&Value>) -> Vec<Value> {
    match system {
        Some(Value::Array(parts)) => parts.clone(),
        Some(Value::Null) | None => Vec::new(),
        Some(single) => vec![single.clone()],
    }
}

fn decode_messages(messages: Option<&Value>) -> Vec<ProtocolIrMessage> {
    let Some(Value::Array(items)) = messages else {
        return Vec::new();
    };

    items
        .iter()
        .filter_map(|item| {
            let obj = item.as_object()?;
            let role = obj
                .get("role")
                .and_then(Value::as_str)
                .unwrap_or("user")
                .to_string();
            let content = obj.get("content").cloned().unwrap_or(Value::Null);
            Some(ProtocolIrMessage { role, content })
        })
        .collect()
}

fn decode_tools(tools: Option<&Value>) -> Vec<Value> {
    let Some(Value::Array(items)) = tools else {
        return Vec::new();
    };
    items.clone()
}

fn collect_extensions(root: &serde_json::Map<String, Value>) -> BTreeMap<String, Value> {
    let mut extensions = BTreeMap::new();
    for (key, value) in root {
        if matches!(key.as_str(), "model" | "system" | "messages" | "tools") {
            continue;
        }
        extensions.insert(key.clone(), value.clone());
    }
    extensions
}
