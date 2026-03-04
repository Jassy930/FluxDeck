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

    let messages = ir
        .messages
        .iter()
        .map(|message| {
            json!({
                "role": &message.role,
                "content": &message.content
            })
        })
        .collect::<Vec<Value>>();

    Ok(json!({
        "model": model,
        "messages": messages,
        "tools": ir.tools
    }))
}

fn encode_error(kind: DecodeErrorKind) -> FluxError {
    FluxError::DecodeError {
        protocol: "openai".to_string(),
        kind,
    }
}
