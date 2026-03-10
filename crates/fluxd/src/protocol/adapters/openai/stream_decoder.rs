use anyhow::{anyhow, Result};
use serde_json::Value;

use crate::protocol::stream::StreamEvent;

pub struct OpenAiSseDecoder {
    pending: Vec<u8>,
    seen_start: bool,
    seen_stop: bool,
}

impl OpenAiSseDecoder {
    pub fn new() -> Self {
        Self {
            pending: Vec::new(),
            seen_start: false,
            seen_stop: false,
        }
    }

    pub fn push_chunk(&mut self, chunk: &[u8]) -> Result<Vec<StreamEvent>> {
        self.pending.extend_from_slice(chunk);

        let mut events = Vec::new();
        while let Some(line_end) = self.pending.iter().position(|item| *item == b'\n') {
            let mut line = self.pending.drain(..=line_end).collect::<Vec<u8>>();
            trim_line_endings(&mut line);
            self.decode_line(&line, &mut events)?;
        }

        Ok(events)
    }

    pub fn finish(&mut self) -> Result<Vec<StreamEvent>> {
        let mut events = Vec::new();

        if !self.pending.is_empty() {
            let mut line = std::mem::take(&mut self.pending);
            trim_line_endings(&mut line);
            self.decode_line(&line, &mut events)?;
        }

        if !self.seen_start {
            events.push(StreamEvent::MessageStart {
                id: "chatcmpl_unknown".to_string(),
                model: None,
            });
            self.seen_start = true;
        }

        if !self.seen_stop {
            events.push(StreamEvent::MessageStop);
            self.seen_stop = true;
        }

        Ok(events)
    }

    fn decode_line(&mut self, raw_line: &[u8], events: &mut Vec<StreamEvent>) -> Result<()> {
        let line = std::str::from_utf8(raw_line)
            .map_err(|err| anyhow!("failed to decode openai sse line as utf-8: {err}"))?
            .trim();

        if !line.starts_with("data:") {
            return Ok(());
        }

        let data = line.trim_start_matches("data:").trim();
        if data.is_empty() {
            return Ok(());
        }

        if data == "[DONE]" {
            if !self.seen_stop {
                events.push(StreamEvent::MessageStop);
                self.seen_stop = true;
            }
            return Ok(());
        }

        let chunk: Value = serde_json::from_str(data)
            .map_err(|err| anyhow!("failed to parse openai sse chunk: {err}"))?;

        if !self.seen_start {
            let id = chunk
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or("chatcmpl_unknown")
                .to_string();
            let model = chunk
                .get("model")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned);
            events.push(StreamEvent::MessageStart { id, model });
            self.seen_start = true;
        }

        if let Some(text) = chunk
            .get("choices")
            .and_then(Value::as_array)
            .and_then(|choices| choices.first())
            .and_then(|choice| choice.get("delta"))
            .and_then(|delta| delta.get("content"))
            .and_then(Value::as_str)
        {
            if !text.is_empty() {
                events.push(StreamEvent::TextDelta {
                    text: text.to_string(),
                });
            }
        }

        // Handle tool_calls in delta
        if let Some(tool_calls) = chunk
            .get("choices")
            .and_then(Value::as_array)
            .and_then(|choices| choices.first())
            .and_then(|choice| choice.get("delta"))
            .and_then(|delta| delta.get("tool_calls"))
            .and_then(Value::as_array)
        {
            for tool_call in tool_calls {
                let index = tool_call
                    .get("index")
                    .and_then(Value::as_u64)
                    .unwrap_or(0) as usize;

                // Check if this is a start chunk (has id and function.name)
                if let (Some(id), Some(name)) = (
                    tool_call.get("id").and_then(Value::as_str),
                    tool_call
                        .get("function")
                        .and_then(|f| f.get("name"))
                        .and_then(Value::as_str),
                ) {
                    events.push(StreamEvent::ToolCallStart {
                        index,
                        id: id.to_string(),
                        name: name.to_string(),
                    });
                }

                // Check for arguments delta
                if let Some(arguments) = tool_call
                    .get("function")
                    .and_then(|f| f.get("arguments"))
                    .and_then(Value::as_str)
                {
                    if !arguments.is_empty() {
                        events.push(StreamEvent::ToolCallDelta {
                            index,
                            arguments: arguments.to_string(),
                        });
                    }
                }
            }
        }

        Ok(())
    }
}

pub fn decode_openai_sse_events(body: &str) -> Result<Vec<StreamEvent>> {
    let mut decoder = OpenAiSseDecoder::new();
    let mut events = decoder.push_chunk(body.as_bytes())?;
    events.extend(decoder.finish()?);
    Ok(events)
}

fn trim_line_endings(line: &mut Vec<u8>) {
    if line.ends_with(b"\n") {
        line.pop();
    }
    if line.ends_with(b"\r") {
        line.pop();
    }
}

#[cfg(test)]
mod tests {
    use super::decode_openai_sse_events;
    use crate::protocol::stream::StreamEvent;

    #[test]
    fn does_not_stop_early_when_finish_reason_arrives_before_done() {
        let body = r#"data: {"id":"chat","choices":[{"index":0,"delta":{"content":"{\n"},"finish_reason":"stop"}]}

data: {"id":"chat","choices":[{"index":0,"delta":{"content":"  \"title\":\"GLM\""}}]}

data: [DONE]

"#;

        let events = decode_openai_sse_events(body).expect("decode stream events");
        assert_eq!(
            events,
            vec![
                StreamEvent::MessageStart {
                    id: "chat".to_string(),
                    model: None
                },
                StreamEvent::TextDelta {
                    text: "{\n".to_string()
                },
                StreamEvent::TextDelta {
                    text: "  \"title\":\"GLM\"".to_string()
                },
                StreamEvent::MessageStop
            ]
        );
    }

    #[test]
    fn decodes_tool_calls_from_sse_stream() {
        let body = r#"data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_123","type":"function","function":{"name":"get_weather","arguments":""}}]},"finish_reason":null}]}

data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"loc"}}]},"finish_reason":null}]}

data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ation\":\""}}]},"finish_reason":null}]}

data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"Tokyo\"}"}}]},"finish_reason":null}]}

data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

"#;

        let events = decode_openai_sse_events(body).expect("decode stream events");
        assert_eq!(
            events,
            vec![
                StreamEvent::MessageStart {
                    id: "chatcmpl-123".to_string(),
                    model: None
                },
                StreamEvent::ToolCallStart {
                    index: 0,
                    id: "call_123".to_string(),
                    name: "get_weather".to_string(),
                },
                StreamEvent::ToolCallDelta {
                    index: 0,
                    arguments: "{\"loc".to_string(),
                },
                StreamEvent::ToolCallDelta {
                    index: 0,
                    arguments: "ation\":\"".to_string(),
                },
                StreamEvent::ToolCallDelta {
                    index: 0,
                    arguments: "Tokyo\"}".to_string(),
                },
                StreamEvent::MessageStop
            ]
        );
    }

    #[test]
    fn decodes_tool_calls_with_empty_first_arguments() {
        // Some models send an empty arguments string in the first chunk
        let body = r#"data: {"id":"chatcmpl-456","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_456","type":"function","function":{"name":"search","arguments":""}}]},"finish_reason":null}]}

data: {"id":"chatcmpl-456","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\":\"test\"}"}}]},"finish_reason":null}]}

data: [DONE]

"#;

        let events = decode_openai_sse_events(body).expect("decode stream events");
        assert_eq!(
            events,
            vec![
                StreamEvent::MessageStart {
                    id: "chatcmpl-456".to_string(),
                    model: None
                },
                StreamEvent::ToolCallStart {
                    index: 0,
                    id: "call_456".to_string(),
                    name: "search".to_string(),
                },
                StreamEvent::ToolCallDelta {
                    index: 0,
                    arguments: "{\"query\":\"test\"}".to_string(),
                },
                StreamEvent::MessageStop
            ]
        );
    }
}
