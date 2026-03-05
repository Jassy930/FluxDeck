use std::collections::BTreeMap;

use serde_json::Value;

use crate::protocol::error::{DecodeErrorKind, FluxError};
use crate::protocol::ir::{IrRequest, ProtocolIrMessage};

pub fn decode_anthropic_request(payload: &Value) -> Result<IrRequest, FluxError> {
    let root = payload
        .as_object()
        .ok_or_else(|| decode_error(DecodeErrorKind::InvalidPayload))?;

    let model = decode_model(root)?;

    let system_parts = decode_system(root.get("system"));
    let messages = decode_messages(root.get("messages"))?;
    let tools = decode_tools(root.get("tools"))?;
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

fn decode_model(root: &serde_json::Map<String, Value>) -> Result<String, FluxError> {
    let Some(model) = root.get("model") else {
        return Err(decode_error(DecodeErrorKind::MissingRequiredField {
            field: "model".to_string(),
        }));
    };

    match model {
        Value::String(value) => Ok(value.clone()),
        other => Err(decode_error(DecodeErrorKind::InvalidFieldType {
            field: "model".to_string(),
            expected: "string".to_string(),
            actual: json_type_name(other).to_string(),
        })),
    }
}

fn decode_messages(messages: Option<&Value>) -> Result<Vec<ProtocolIrMessage>, FluxError> {
    let Some(raw_messages) = messages else {
        return Ok(Vec::new());
    };

    let Value::Array(items) = raw_messages else {
        return Err(decode_error(DecodeErrorKind::InvalidFieldType {
            field: "messages".to_string(),
            expected: "array".to_string(),
            actual: json_type_name(raw_messages).to_string(),
        }));
    };

    let mut decoded = Vec::with_capacity(items.len());
    for (index, message) in items.iter().enumerate() {
        let Some(obj) = message.as_object() else {
            return Err(decode_error(DecodeErrorKind::InvalidFieldType {
                field: format!("messages[{index}]"),
                expected: "object".to_string(),
                actual: json_type_name(message).to_string(),
            }));
        };

        let role = obj
            .get("role")
            .and_then(Value::as_str)
            .unwrap_or("user")
            .to_string();
        let content = obj.get("content").cloned().unwrap_or(Value::Null);
        decoded.push(ProtocolIrMessage { role, content });
    }

    Ok(decoded)
}

fn decode_tools(tools: Option<&Value>) -> Result<Vec<Value>, FluxError> {
    let Some(raw_tools) = tools else {
        return Ok(Vec::new());
    };

    let Value::Array(items) = raw_tools else {
        return Err(decode_error(DecodeErrorKind::InvalidFieldType {
            field: "tools".to_string(),
            expected: "array".to_string(),
            actual: json_type_name(raw_tools).to_string(),
        }));
    };

    Ok(items.clone())
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

fn decode_error(kind: DecodeErrorKind) -> FluxError {
    FluxError::DecodeError {
        protocol: "anthropic".to_string(),
        kind,
    }
}

fn json_type_name(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}
