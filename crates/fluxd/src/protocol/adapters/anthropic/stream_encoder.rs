use serde_json::{json, Value};

use crate::protocol::stream::StreamEvent;

pub fn encode_anthropic_sse(events: &[StreamEvent]) -> String {
    let mut message_id = "msg_chatcmpl_unknown".to_string();
    let mut model: Option<String> = None;
    let mut deltas = Vec::new();

    for event in events {
        match event {
            StreamEvent::MessageStart {
                id,
                model: event_model,
            } => {
                message_id = normalize_message_id(id);
                model = event_model.clone();
            }
            StreamEvent::TextDelta { text } => {
                deltas.push(text.clone());
            }
            StreamEvent::MessageStop => {}
        }
    }

    let mut body = String::new();

    push_event(
        &mut body,
        "message_start",
        json!({
            "type": "message_start",
            "message": {
                "id": message_id,
                "type": "message",
                "role": "assistant",
                "model": model,
                "content": [],
                "stop_reason": Value::Null,
                "stop_sequence": Value::Null,
                "usage": {
                    "input_tokens": 0,
                    "output_tokens": 0
                }
            }
        }),
    );

    if !deltas.is_empty() {
        push_event(
            &mut body,
            "content_block_start",
            json!({
                "type": "content_block_start",
                "index": 0,
                "content_block": {
                    "type": "text",
                    "text": ""
                }
            }),
        );

        for delta in deltas {
            push_event(
                &mut body,
                "content_block_delta",
                json!({
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": {
                        "type": "text_delta",
                        "text": delta
                    }
                }),
            );
        }

        push_event(
            &mut body,
            "content_block_stop",
            json!({
                "type": "content_block_stop",
                "index": 0
            }),
        );
    }

    push_event(&mut body, "message_stop", json!({ "type": "message_stop" }));

    body
}

fn normalize_message_id(id: &str) -> String {
    if id.starts_with("msg_") {
        id.to_string()
    } else {
        format!("msg_{id}")
    }
}

fn push_event(body: &mut String, event: &str, data: Value) {
    body.push_str("event: ");
    body.push_str(event);
    body.push('\n');
    body.push_str("data: ");
    body.push_str(&data.to_string());
    body.push_str("\n\n");
}
