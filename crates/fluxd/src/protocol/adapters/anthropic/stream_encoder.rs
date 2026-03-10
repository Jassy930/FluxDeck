use serde_json::{json, Value};

use crate::protocol::stream::StreamEvent;

pub struct AnthropicSseEncoder {
    message_id: String,
    model: Option<String>,
    sent_message_start: bool,
    current_content_block_index: Option<usize>,
}

impl AnthropicSseEncoder {
    pub fn new() -> Self {
        Self {
            message_id: "msg_chatcmpl_unknown".to_string(),
            model: None,
            sent_message_start: false,
            current_content_block_index: None,
        }
    }

    pub fn encode_event(&mut self, event: &StreamEvent) -> String {
        let mut body = String::new();
        match event {
            StreamEvent::MessageStart {
                id,
                model: event_model,
            } => {
                self.message_id = normalize_message_id(id);
                self.model = event_model.clone();
                if !self.sent_message_start {
                    self.push_message_start(&mut body);
                    self.sent_message_start = true;
                }
            }
            StreamEvent::TextDelta { text } => {
                if !self.sent_message_start {
                    self.push_message_start(&mut body);
                    self.sent_message_start = true;
                }
                // Close any open tool_use block before starting text block
                if let Some(idx) = self.current_content_block_index {
                    push_event(
                        &mut body,
                        "content_block_stop",
                        json!({
                            "type": "content_block_stop",
                            "index": idx
                        }),
                    );
                    self.current_content_block_index = None;
                }
                // Start text block at index 0 if not already open
                if self.current_content_block_index.is_none() {
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
                    self.current_content_block_index = Some(0);
                }

                push_event(
                    &mut body,
                    "content_block_delta",
                    json!({
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {
                            "type": "text_delta",
                            "text": text
                        }
                    }),
                );
            }
            StreamEvent::ToolCallStart { index, id, name } => {
                if !self.sent_message_start {
                    self.push_message_start(&mut body);
                    self.sent_message_start = true;
                }
                // Close any open content block
                if let Some(idx) = self.current_content_block_index {
                    push_event(
                        &mut body,
                        "content_block_stop",
                        json!({
                            "type": "content_block_stop",
                            "index": idx
                        }),
                    );
                }
                // Start a new tool_use block
                push_event(
                    &mut body,
                    "content_block_start",
                    json!({
                        "type": "content_block_start",
                        "index": index,
                        "content_block": {
                            "type": "tool_use",
                            "id": id,
                            "name": name,
                            "input": {}
                        }
                    }),
                );
                self.current_content_block_index = Some(*index);
            }
            StreamEvent::ToolCallDelta { index, arguments } => {
                if !self.sent_message_start {
                    self.push_message_start(&mut body);
                    self.sent_message_start = true;
                }
                push_event(
                    &mut body,
                    "content_block_delta",
                    json!({
                        "type": "content_block_delta",
                        "index": index,
                        "delta": {
                            "type": "input_json_delta",
                            "partial_json": arguments
                        }
                    }),
                );
            }
            StreamEvent::MessageStop => {
                if !self.sent_message_start {
                    self.push_message_start(&mut body);
                    self.sent_message_start = true;
                }
                if let Some(idx) = self.current_content_block_index {
                    push_event(
                        &mut body,
                        "content_block_stop",
                        json!({
                            "type": "content_block_stop",
                            "index": idx
                        }),
                    );
                    self.current_content_block_index = None;
                }
                push_event(&mut body, "message_stop", json!({ "type": "message_stop" }));
            }
        }

        body
    }

    fn push_message_start(&self, body: &mut String) {
        push_event(
            body,
            "message_start",
            json!({
                "type": "message_start",
                "message": {
                    "id": self.message_id,
                    "type": "message",
                    "role": "assistant",
                    "model": self.model,
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
    }
}

pub fn encode_anthropic_sse(events: &[StreamEvent]) -> String {
    let mut encoder = AnthropicSseEncoder::new();
    let mut body = String::new();
    for event in events {
        let chunk = encoder.encode_event(event);
        if !chunk.is_empty() {
            body.push_str(&chunk);
        }
    }

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
