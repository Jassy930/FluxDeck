use serde_json::{json, Value};

use crate::protocol::ir::IrRequest;

pub fn map_openai_to_anthropic_message(openai_response: &Value, ir: &IrRequest) -> Value {
    let openai_id = openai_response
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let anthropic_id = if openai_id.starts_with("msg_") {
        openai_id.to_string()
    } else {
        format!("msg_{openai_id}")
    };

    let first_choice = openai_response
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first());

    let finish_reason = first_choice
        .and_then(|choice| choice.get("finish_reason"))
        .and_then(Value::as_str);

    let first_message = first_choice.and_then(|choice| choice.get("message"));

    let message_content = first_message
        .and_then(|message| message.get("content"))
        .cloned()
        .unwrap_or(Value::Null);

    let mut content = map_content_to_anthropic_blocks(&message_content);
    content.extend(map_tool_calls_to_anthropic_blocks(
        first_message.and_then(|message| message.get("tool_calls")),
    ));
    let has_tool_use_block = content
        .iter()
        .any(|block| block.get("type").and_then(Value::as_str) == Some("tool_use"));

    let usage = openai_response.get("usage").and_then(Value::as_object);
    let input_tokens = usage
        .and_then(|item| item.get("prompt_tokens"))
        .cloned()
        .unwrap_or_else(|| json!(0));
    let output_tokens = usage
        .and_then(|item| item.get("completion_tokens"))
        .cloned()
        .unwrap_or_else(|| json!(0));

    let model = openai_response
        .get("model")
        .cloned()
        .or_else(|| ir.model.as_ref().map(|item| json!(item)))
        .unwrap_or(Value::Null);

    json!({
        "id": anthropic_id,
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": content,
        "stop_reason": map_finish_reason(finish_reason, has_tool_use_block),
        "stop_sequence": Value::Null,
        "usage": {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens
        }
    })
}

fn map_content_to_anthropic_blocks(content: &Value) -> Vec<Value> {
    match content {
        Value::String(text) => vec![json!({
            "type": "text",
            "text": text
        })],
        Value::Array(items) => items.iter().filter_map(map_openai_content_item).collect(),
        Value::Null => Vec::new(),
        other => vec![json!({
            "type": "text",
            "text": stringify_value(other)
        })],
    }
}

fn map_openai_content_item(item: &Value) -> Option<Value> {
    match item {
        Value::String(text) => Some(json!({
            "type": "text",
            "text": text
        })),
        Value::Object(object) => {
            let text = object
                .get("text")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
                .or_else(|| Some(stringify_value(item)))?;

            Some(json!({
                "type": "text",
                "text": text
            }))
        }
        Value::Null => None,
        other => Some(json!({
            "type": "text",
            "text": stringify_value(other)
        })),
    }
}

fn map_tool_calls_to_anthropic_blocks(tool_calls: Option<&Value>) -> Vec<Value> {
    match tool_calls {
        Some(Value::Array(items)) => items.iter().filter_map(map_openai_tool_call_item).collect(),
        _ => Vec::new(),
    }
}

fn map_openai_tool_call_item(item: &Value) -> Option<Value> {
    let object = item.as_object()?;
    let name = object
        .get("function")
        .and_then(Value::as_object)
        .and_then(|function| function.get("name"))
        .and_then(Value::as_str)?;
    let id = object
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or("toolu_unknown");

    let input = object
        .get("function")
        .and_then(Value::as_object)
        .and_then(|function| function.get("arguments"))
        .map(parse_openai_tool_arguments)
        .unwrap_or_else(|| json!({}));

    Some(json!({
        "type": "tool_use",
        "id": id,
        "name": name,
        "input": input
    }))
}

fn parse_openai_tool_arguments(arguments: &Value) -> Value {
    match arguments {
        Value::String(raw) => match serde_json::from_str::<Value>(raw) {
            Ok(object @ Value::Object(_)) => object,
            Ok(other) => json!({ "_value": other }),
            Err(_) => json!({ "_raw": raw }),
        },
        Value::Object(_) => arguments.clone(),
        Value::Null => json!({}),
        other => json!({ "_value": other }),
    }
}

fn map_finish_reason(finish_reason: Option<&str>, has_tool_use_block: bool) -> Value {
    match finish_reason {
        Some("stop") => json!("end_turn"),
        Some("length") => json!("max_tokens"),
        Some("tool_calls") if has_tool_use_block => json!("tool_use"),
        Some("tool_calls") => Value::Null,
        _ => Value::Null,
    }
}

fn stringify_value(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| String::new())
}
