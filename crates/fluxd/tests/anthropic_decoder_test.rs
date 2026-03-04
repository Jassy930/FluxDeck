use fluxd::protocol::adapters::anthropic::decode_anthropic_request;
use fluxd::protocol::error::{DecodeErrorKind, FluxError};
use serde_json::json;

#[test]
fn decode_anthropic_request_maps_messages_system_tools_to_ir() {
    let payload = json!({
        "model": "claude-3-7-sonnet",
        "system": "you are helpful",
        "messages": [
            {
                "role": "user",
                "content": "hello"
            }
        ],
        "tools": [
            {
                "name": "weather",
                "input_schema": {
                    "type": "object"
                }
            }
        ],
        "temperature": 0.3,
        "x_extra": {
            "trace_id": "req-1"
        }
    });

    let ir = decode_anthropic_request(&payload).expect("decode anthropic request");
    assert_eq!(ir.model.as_deref(), Some("claude-3-7-sonnet"));
    assert_eq!(ir.system_parts.len(), 1);
    assert_eq!(ir.tools.len(), 1);
    assert_eq!(ir.extensions.get("temperature"), Some(&json!(0.3)));
    assert_eq!(
        ir.extensions.get("x_extra"),
        Some(&json!({ "trace_id": "req-1" }))
    );
}

#[test]
fn decode_anthropic_request_requires_model() {
    let payload = json!({
        "messages": [
            {
                "role": "user",
                "content": "hello"
            }
        ]
    });

    let result = decode_anthropic_request(&payload);
    assert_eq!(
        result,
        Err(FluxError::DecodeError {
            protocol: "anthropic".to_string(),
            kind: DecodeErrorKind::MissingRequiredField {
                field: "model".to_string(),
            },
        })
    );
}

#[test]
fn decode_anthropic_request_rejects_non_array_messages() {
    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": {
            "role": "user",
            "content": "hello"
        }
    });

    let result = decode_anthropic_request(&payload);
    assert_eq!(
        result,
        Err(FluxError::DecodeError {
            protocol: "anthropic".to_string(),
            kind: DecodeErrorKind::InvalidFieldType {
                field: "messages".to_string(),
                expected: "array".to_string(),
                actual: "object".to_string(),
            },
        })
    );
}

#[test]
fn decode_anthropic_request_rejects_non_array_tools() {
    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": [],
        "tools": {
            "name": "weather"
        }
    });

    let result = decode_anthropic_request(&payload);
    assert_eq!(
        result,
        Err(FluxError::DecodeError {
            protocol: "anthropic".to_string(),
            kind: DecodeErrorKind::InvalidFieldType {
                field: "tools".to_string(),
                expected: "array".to_string(),
                actual: "object".to_string(),
            },
        })
    );
}

#[test]
fn decode_anthropic_request_rejects_non_object_message_item() {
    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": [
            "hello"
        ]
    });

    let result = decode_anthropic_request(&payload);
    assert_eq!(
        result,
        Err(FluxError::DecodeError {
            protocol: "anthropic".to_string(),
            kind: DecodeErrorKind::InvalidFieldType {
                field: "messages[0]".to_string(),
                expected: "object".to_string(),
                actual: "string".to_string(),
            },
        })
    );
}

#[test]
fn decode_anthropic_request_rejects_non_string_model() {
    let payload = json!({
        "model": 7,
        "messages": []
    });

    let result = decode_anthropic_request(&payload);
    assert_eq!(
        result,
        Err(FluxError::DecodeError {
            protocol: "anthropic".to_string(),
            kind: DecodeErrorKind::InvalidFieldType {
                field: "model".to_string(),
                expected: "string".to_string(),
                actual: "number".to_string(),
            },
        })
    );
}
