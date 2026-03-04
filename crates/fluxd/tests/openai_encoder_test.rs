use std::collections::BTreeMap;

use fluxd::protocol::adapters::openai::encode_openai_chat_request;
use fluxd::protocol::error::{DecodeErrorKind, FluxError};
use fluxd::protocol::ir::{IrRequest, ProtocolIrMessage};
use serde_json::{json, Value};

#[test]
fn encodes_ir_to_openai_chat_payload() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: Value::String("hello".to_string()),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode openai chat request");

    assert_eq!(payload["model"], "gpt-4o-mini");
    assert_eq!(payload["messages"][0]["role"], "user");
    assert_eq!(payload["messages"][0]["content"], json!("hello"));
}

#[test]
fn maps_system_parts_to_openai_system_messages() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: vec![
            Value::String("you are helpful".to_string()),
            json!({"type": "text", "text": "be concise"}),
        ],
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: Value::String("hello".to_string()),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode with system parts");

    assert_eq!(payload["messages"][0]["role"], "system");
    assert_eq!(payload["messages"][0]["content"], json!("you are helpful"));
    assert_eq!(payload["messages"][1]["role"], "system");
    assert_eq!(
        payload["messages"][1]["content"],
        json!({"type": "text", "text": "be concise"})
    );
    assert_eq!(payload["messages"][2]["role"], "user");
}

#[test]
fn normalizes_anthropic_tools_to_openai_function_tools() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: Value::String("hello".to_string()),
        }],
        tools: vec![json!({
            "name": "weather",
            "input_schema": {
                "type": "object",
                "properties": {
                    "city": {"type": "string"}
                },
                "required": ["city"]
            }
        })],
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode with tools");

    assert_eq!(payload["tools"][0]["type"], "function");
    assert_eq!(payload["tools"][0]["function"]["name"], "weather");
    assert_eq!(
        payload["tools"][0]["function"]["parameters"],
        json!({
            "type": "object",
            "properties": {
                "city": {"type": "string"}
            },
            "required": ["city"]
        })
    );
    assert_eq!(payload["tools"][0]["input_schema"], Value::Null);
}

#[test]
fn returns_error_when_model_missing() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: None,
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: Value::String("hello".to_string()),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let result = encode_openai_chat_request(&ir);
    assert_eq!(
        result,
        Err(FluxError::DecodeError {
            protocol: "openai".to_string(),
            kind: DecodeErrorKind::MissingRequiredField {
                field: "model".to_string(),
            },
        })
    );
}

#[test]
fn returns_error_when_tool_name_missing() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: Value::String("hello".to_string()),
        }],
        tools: vec![json!({
            "input_schema": {
                "type": "object"
            }
        })],
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let result = encode_openai_chat_request(&ir);
    assert_eq!(
        result,
        Err(FluxError::DecodeError {
            protocol: "openai".to_string(),
            kind: DecodeErrorKind::MissingRequiredField {
                field: "tools[0].name".to_string(),
            },
        })
    );
}

#[test]
fn returns_error_when_tool_input_schema_missing() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: Value::String("hello".to_string()),
        }],
        tools: vec![json!({
            "name": "weather"
        })],
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let result = encode_openai_chat_request(&ir);
    assert_eq!(
        result,
        Err(FluxError::DecodeError {
            protocol: "openai".to_string(),
            kind: DecodeErrorKind::MissingRequiredField {
                field: "tools[0].input_schema".to_string(),
            },
        })
    );
}

#[test]
fn returns_error_when_tool_is_not_object() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: Value::String("hello".to_string()),
        }],
        tools: vec![Value::String("weather".to_string())],
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let result = encode_openai_chat_request(&ir);
    assert_eq!(
        result,
        Err(FluxError::DecodeError {
            protocol: "openai".to_string(),
            kind: DecodeErrorKind::InvalidFieldType {
                field: "tools[0]".to_string(),
                expected: "object".to_string(),
                actual: "string".to_string(),
            },
        })
    );
}
