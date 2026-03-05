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
            "content": part
        }));
    }
    for message in &ir.messages {
        messages.push(json!({
            "role": &message.role,
            "content": &message.content
        }));
    }

    let tools = normalize_tools(&ir.tools)?;

    Ok(json!({
        "model": model,
        "messages": messages,
        "tools": tools
    }))
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
