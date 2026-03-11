use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};

use crate::protocol::error::{DecodeErrorKind, FluxError};
use crate::protocol::ir::IrRequest;

static TOOL_ID_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Sanitizes a string to contain only alphanumeric, underscore, and hyphen characters.
/// Anthropic requires tool_use IDs to match pattern `^[a-zA-Z0-9_-]+$`.
fn sanitize_tool_id_for_request(id: &str) -> String {
    let sanitized: String = id
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
        .collect();
    if sanitized.is_empty() {
        let count = TOOL_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
        format!("toolu_{count}")
    } else {
        sanitized
    }
}

/// Result of processing an Anthropic message content for OpenAI format
struct ProcessedMessage {
    /// The main message (may have tool_calls attached), None if only tool_results
    main_message: Option<Value>,
    /// Additional tool result messages (role: "tool")
    tool_messages: Vec<Value>,
}

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
            "content": normalize_content_for_openai(part)
        }));
    }
    for message in &ir.messages {
        let processed = process_anthropic_message(&message.role, &message.content);
        // Only add main_message if it exists (it may be None for tool_result-only messages)
        if let Some(main_msg) = processed.main_message {
            messages.push(main_msg);
        }
        messages.extend(processed.tool_messages);
    }

    let tools = normalize_tools(&ir.tools)?;

    let mut payload = if tools.is_empty() {
        json!({
            "model": model,
            "messages": messages
        })
    } else {
        json!({
            "model": model,
            "messages": messages,
            "tools": tools
        })
    };
    apply_common_anthropic_extensions(ir, &mut payload);

    Ok(payload)
}

/// Process an Anthropic message and convert it to OpenAI format
fn process_anthropic_message(role: &str, content: &Value) -> ProcessedMessage {
    let content_blocks = match content {
        Value::Array(blocks) => blocks.clone(),
        Value::String(text) => {
            return ProcessedMessage {
                main_message: Some(json!({
                    "role": role,
                    "content": text
                })),
                tool_messages: Vec::new(),
            };
        }
        Value::Null => {
            return ProcessedMessage {
                main_message: Some(json!({
                    "role": role,
                    "content": Value::Null
                })),
                tool_messages: Vec::new(),
            };
        }
        other => {
            // Try to extract text from single object
            if let Some(text) = extract_text_block_text(other) {
                return ProcessedMessage {
                    main_message: Some(json!({
                        "role": role,
                        "content": text
                    })),
                    tool_messages: Vec::new(),
                };
            }
            vec![other.clone()]
        }
    };

    let mut text_parts: Vec<String> = Vec::new();
    let mut tool_calls: Vec<Value> = Vec::new();
    let mut tool_messages: Vec<Value> = Vec::new();

    for block in &content_blocks {
        let block_type = block
            .as_object()
            .and_then(|obj| obj.get("type").and_then(Value::as_str));

        match block_type {
            Some("text") => {
                if let Some(text) = block.get("text").and_then(Value::as_str) {
                    text_parts.push(text.to_string());
                }
            }
            Some("tool_use") => {
                if let Some(tool_call) = convert_tool_use_to_openai(block) {
                    tool_calls.push(tool_call);
                }
            }
            Some("tool_result") => {
                if let Some(tool_msg) = convert_tool_result_to_openai(block) {
                    tool_messages.push(tool_msg);
                }
            }
            Some("image") => {
                // Convert Anthropic image to OpenAI image_url format
                if let Some(image_content) = convert_image_to_openai(block) {
                    text_parts.push(image_content);
                }
            }
            Some("thinking") => {
                // OpenAI doesn't support thinking blocks, skip them
                continue;
            }
            _ => {
                // For unknown types, try to extract as text or skip
                if let Some(text) = extract_text_block_text(block) {
                    text_parts.push(text.to_string());
                }
            }
        }
    }

    // Build the main message only if there's content or tool_calls
    // If the message only contains tool_results, skip the main message entirely
    let main_message = if text_parts.is_empty() && tool_calls.is_empty() {
        // Only tool_results - don't create a main message with null content
        None
    } else {
        let content_value = if text_parts.is_empty() {
            Value::Null
        } else {
            Value::String(text_parts.join("\n"))
        };

        let mut msg = json!({
            "role": role,
            "content": content_value
        });

        // Attach tool_calls if present (for assistant messages)
        if !tool_calls.is_empty() {
            if let Some(obj) = msg.as_object_mut() {
                obj.insert("tool_calls".to_string(), Value::Array(tool_calls));
            }
        }

        Some(msg)
    };

    ProcessedMessage {
        main_message,
        tool_messages,
    }
}

/// Convert Anthropic tool_use block to OpenAI tool_call format
fn convert_tool_use_to_openai(block: &Value) -> Option<Value> {
    let obj = block.as_object()?;
    let raw_id = obj.get("id").and_then(Value::as_str).unwrap_or("");
    let name = obj.get("name").and_then(Value::as_str)?;

    // Sanitize ID to match Anthropic's pattern requirement
    let id = sanitize_tool_id_for_request(raw_id);

    // Arguments should be a JSON string in OpenAI format
    let input = obj.get("input").cloned().unwrap_or(json!({}));
    let arguments = serde_json::to_string(&input).unwrap_or_else(|_| "{}".to_string());

    Some(json!({
        "id": id,
        "type": "function",
        "function": {
            "name": name,
            "arguments": arguments
        }
    }))
}

/// Convert Anthropic tool_result block to OpenAI tool message format
fn convert_tool_result_to_openai(block: &Value) -> Option<Value> {
    let obj = block.as_object()?;
    let tool_use_id = obj.get("tool_use_id").and_then(Value::as_str)?;

    // Extract content from tool_result
    let content = match obj.get("content") {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Array(blocks)) => {
            // Join text blocks, serialize others
            let parts: Vec<String> = blocks
                .iter()
                .filter_map(|b| match b {
                    Value::String(s) => Some(s.clone()),
                    other => other.get("text").and_then(Value::as_str).map(ToOwned::to_owned),
                })
                .collect();
            parts.join("\n")
        }
        Some(other) => serde_json::to_string(other).unwrap_or_default(),
        None => String::new(),
    };

    Some(json!({
        "role": "tool",
        "tool_call_id": tool_use_id,
        "content": content
    }))
}

/// Convert Anthropic image block to OpenAI image_url format (returns text description for now)
fn convert_image_to_openai(block: &Value) -> Option<String> {
    let obj = block.as_object();

    // For now, we'll skip image conversion in text content
    // Images need to be handled as separate content parts in OpenAI format
    // This is a placeholder - full image support would require restructuring the message format
    let _ = obj;
    None
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

fn normalize_content_for_openai(value: &Value) -> Value {
    if let Some(text) = extract_text_block_text(value) {
        return Value::String(text.to_string());
    }

    if let Some(joined) = join_text_blocks(value) {
        return Value::String(joined);
    }

    sanitize_for_openai(value)
}

fn extract_text_block_text(value: &Value) -> Option<&str> {
    let object = value.as_object()?;
    let block_type = object.get("type")?.as_str()?;
    if block_type != "text" {
        return None;
    }
    object.get("text")?.as_str()
}

fn join_text_blocks(value: &Value) -> Option<String> {
    let items = value.as_array()?;
    if items.is_empty() {
        return Some(String::new());
    }

    let mut chunks = Vec::with_capacity(items.len());
    for item in items {
        if let Some(text) = item.as_str() {
            chunks.push(text.to_string());
            continue;
        }
        if let Some(text) = extract_text_block_text(item) {
            chunks.push(text.to_string());
            continue;
        }
        return None;
    }

    Some(chunks.join("\n"))
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
