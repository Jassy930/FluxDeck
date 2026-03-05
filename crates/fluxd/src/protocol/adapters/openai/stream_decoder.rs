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

        let finish_reason = chunk
            .get("choices")
            .and_then(Value::as_array)
            .and_then(|choices| choices.first())
            .and_then(|choice| choice.get("finish_reason"))
            .and_then(Value::as_str);

        if finish_reason.is_some() && !self.seen_stop {
            events.push(StreamEvent::MessageStop);
            self.seen_stop = true;
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
