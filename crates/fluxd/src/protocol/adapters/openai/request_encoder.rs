use serde_json::{json, Value};

use crate::protocol::error::{DecodeErrorKind, FluxError};
use crate::protocol::ir::IrRequest;

pub fn encode_openai_chat_request(ir: &IrRequest) -> Result<Value, FluxError> {
    let model = ir
        .model
        .as_ref()
        .ok_or_else(|| encode_error(DecodeErrorKind::MissingRequiredField {
            field: "model".to_string(),
        }))?;

    let mut messages = Vec::with_capacity(ir.system_parts.len() + ir.messages.len());
    for part in &ir.system_parts {
        messages.push(json!({
            "role": "system",
            "content": sanitize_for_openai(part)
        }));
    }
    for message in &ir.messages {
        messages.push(json!({
            "role": &message.role,
            "content": sanitize_for_openai(&message.content)
        }));
    }

    let tools = normalize_tools(&ir.tools)?;

    let mut payload = json!({
        "model": model,
        "messages": messages,
        "tools": tools
    });
    apply_common_anthropic_extensions(ir, &mut payload);

    Ok(payload)
}

fn apply_common_anthropic_extensions(ir: &IrRequest, payload: &mut Value) {
    let Some(object) = payload.as_object_mut() else {
        return;
    };

    copy_extension_if_present(ir, object, "max_tokens", "max_tokens");
    copy_extension_if_present(ir, object, "temperature", "temperature");
    copy_extension_if_present(ir, object, "top_p", "top_p");
    copy_extension_if_present(ir, object, "tool_choice", "tool_choice");
    copy_extension_if_present(ir, object, "metadata", "metadata");

    if let Some(value) = ir.extensions.get("stop_sequences") {
        object.insert("stop".to_string(), value.clone());
    }
}

fn copy_extension_if_present(
    ir: &IrRequest,
    payload: &mut serde_json::Map<String, Value>,
    source_key: &str,
    target_key: &str,
) {
    if let Some(value) = ir.extensions.get(source_key) {
        payload.insert(target_key.to_string(), value.clone());
    }
}

fn sanitize_for_openai(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let mut next = serde_json::Map::new();
            for (key, item) in map {
                if key == "cache_control" {
                    continue;
                }
                next.insert(key.clone(), sanitize_for_openai(item));
            }
            Value::Object(next)
        }
        Value::Array(items) => Value::Array(items.iter().map(sanitize_for_openai).collect()),
        _ => value.clone(),
    }
}

fn normalize_tools(tools: &[Value]) -> Result<Vec<Value>, FluxError> {
    tools
        .iter()
        .enumerate()
        .map(|(index, tool)| normalize_tool(tool, index))
        .collect()
}

fn normalize_tool(tool: &Value, index: usize) -> Result<Value, FluxError> {
    let Some(object) = tool.as_object() else {
        return Err(encode_error(DecodeErrorKind::InvalidFieldType {
            field: format!("tools[{index}]"),
            expected: "object".to_string(),
            actual: json_type_name(tool).to_string(),
        }));
    };

    let Some(name) = object.get("name").and_then(Value::as_str) else {
        return Err(encode_error(DecodeErrorKind::MissingRequiredField {
            field: format!("tools[{index}].name"),
        }));
    };
    let Some(parameters) = object.get("input_schema") else {
        return Err(encode_error(DecodeErrorKind::MissingRequiredField {
            field: format!("tools[{index}].input_schema"),
        }));
    };

    Ok(json!({
        "type": "function",
        "function": {
            "name": name,
            "parameters": parameters
        }
    }))
}

fn encode_error(kind: DecodeErrorKind) -> FluxError {
    FluxError::DecodeError {
        protocol: "openai".to_string(),
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
