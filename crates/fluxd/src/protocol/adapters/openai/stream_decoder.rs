use anyhow::{anyhow, Result};
use serde_json::Value;

use crate::protocol::stream::StreamEvent;

pub fn decode_openai_sse_events(body: &str) -> Result<Vec<StreamEvent>> {
    let mut events = Vec::new();
    let mut seen_start = false;
    let mut seen_stop = false;

    for raw_line in body.lines() {
        let line = raw_line.trim();
        if !line.starts_with("data:") {
            continue;
        }

        let data = line.trim_start_matches("data:").trim();
        if data.is_empty() {
            continue;
        }

        if data == "[DONE]" {
            if !seen_stop {
                events.push(StreamEvent::MessageStop);
                seen_stop = true;
            }
            continue;
        }

        let chunk: Value = serde_json::from_str(data)
            .map_err(|err| anyhow!("failed to parse openai sse chunk: {err}"))?;

        if !seen_start {
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
            seen_start = true;
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

        let finish_reason = chunk
            .get("choices")
            .and_then(Value::as_array)
            .and_then(|choices| choices.first())
            .and_then(|choice| choice.get("finish_reason"))
            .and_then(Value::as_str);

        if finish_reason.is_some() && !seen_stop {
            events.push(StreamEvent::MessageStop);
            seen_stop = true;
        }
    }

    if !seen_start {
        events.push(StreamEvent::MessageStart {
            id: "chatcmpl_unknown".to_string(),
            model: None,
        });
    }

    if !seen_stop {
        events.push(StreamEvent::MessageStop);
    }

    Ok(events)
}
