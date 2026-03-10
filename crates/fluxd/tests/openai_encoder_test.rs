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
    assert_eq!(payload["messages"][1]["content"], json!("be concise"));
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

#[test]
fn maps_common_anthropic_extensions_to_openai_fields() {
    let mut extensions = BTreeMap::new();
    extensions.insert("max_tokens".to_string(), json!(512));
    extensions.insert("temperature".to_string(), json!(0.2));
    extensions.insert("top_p".to_string(), json!(0.9));
    extensions.insert("stop_sequences".to_string(), json!(["\n\nHuman:"]));

    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("qwen3-coder-plus".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: Value::String("hello".to_string()),
        }],
        tools: Vec::new(),
        extensions,
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode with anthropic extensions");

    assert_eq!(payload["max_tokens"], json!(512));
    assert_eq!(payload["temperature"], json!(0.2));
    assert_eq!(payload["top_p"], json!(0.9));
    assert_eq!(payload["stop"], json!(["\n\nHuman:"]));
}

#[test]
fn strips_cache_control_from_anthropic_content_blocks() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("qwen3-coder-plus".to_string()),
        system_parts: vec![json!({
            "type": "text",
            "text": "sys",
            "cache_control": {"type": "ephemeral"}
        })],
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: json!([
                {
                    "type": "text",
                    "text": "hello",
                    "cache_control": {"type": "ephemeral"}
                }
            ]),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode and sanitize content");

    assert_eq!(payload["messages"][0]["content"], json!("sys"));
    assert_eq!(payload["messages"][1]["content"], json!("hello"));
}

#[test]
fn normalizes_text_block_array_to_string_content() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("qwen3-coder-plus".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: json!([
                {"type":"text","text":"line1"},
                {"type":"text","text":"line2"}
            ]),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode text block array");
    assert_eq!(payload["messages"][0]["content"], json!("line1\nline2"));
}

#[test]
fn converts_tool_use_to_openai_tool_calls() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "assistant".to_string(),
            content: json!([
                {"type": "text", "text": "Let me check the weather."},
                {
                    "type": "tool_use",
                    "id": "toolu_123",
                    "name": "get_weather",
                    "input": {"city": "Beijing"}
                }
            ]),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode tool_use");

    assert_eq!(payload["messages"][0]["role"], "assistant");
    assert_eq!(payload["messages"][0]["content"], "Let me check the weather.");
    assert_eq!(payload["messages"][0]["tool_calls"][0]["id"], "toolu_123");
    assert_eq!(payload["messages"][0]["tool_calls"][0]["type"], "function");
    assert_eq!(payload["messages"][0]["tool_calls"][0]["function"]["name"], "get_weather");
    assert_eq!(
        payload["messages"][0]["tool_calls"][0]["function"]["arguments"],
        r#"{"city":"Beijing"}"#
    );
}

#[test]
fn converts_tool_result_to_openai_tool_message() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: json!([
                {
                    "type": "tool_result",
                    "tool_use_id": "toolu_123",
                    "content": "The weather in Beijing is sunny."
                }
            ]),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode tool_result");

    // The user message with only tool_result is converted directly to tool message
    // No empty user message with null content
    assert_eq!(payload["messages"][0]["role"], "tool");
    assert_eq!(payload["messages"][0]["tool_call_id"], "toolu_123");
    assert_eq!(payload["messages"][0]["content"], "The weather in Beijing is sunny.");
}

#[test]
fn handles_multi_turn_tool_conversation() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![
            ProtocolIrMessage {
                role: "user".to_string(),
                content: json!("What's the weather in Beijing?"),
            },
            ProtocolIrMessage {
                role: "assistant".to_string(),
                content: json!([
                    {
                        "type": "tool_use",
                        "id": "toolu_001",
                        "name": "get_weather",
                        "input": {"city": "Beijing"}
                    }
                ]),
            },
            ProtocolIrMessage {
                role: "user".to_string(),
                content: json!([
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_001",
                        "content": "Sunny, 25°C"
                    }
                ]),
            },
        ],
        tools: vec![json!({
            "name": "get_weather",
            "input_schema": {"type": "object", "properties": {"city": {"type": "string"}}}
        })],
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode multi-turn tool conversation");

    // user: "What's the weather?"
    assert_eq!(payload["messages"][0]["role"], "user");
    assert_eq!(payload["messages"][0]["content"], "What's the weather in Beijing?");

    // assistant with tool_call
    assert_eq!(payload["messages"][1]["role"], "assistant");
    assert_eq!(payload["messages"][1]["content"], Value::Null);
    assert_eq!(payload["messages"][1]["tool_calls"][0]["id"], "toolu_001");

    // tool result (no empty user message before it)
    // The user message with only tool_result is converted directly to tool message
    assert_eq!(payload["messages"][2]["role"], "tool");
    assert_eq!(payload["messages"][2]["tool_call_id"], "toolu_001");
    assert_eq!(payload["messages"][2]["content"], "Sunny, 25°C");
}

#[test]
fn handles_multiple_tool_uses_in_single_message() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "assistant".to_string(),
            content: json!([
                {
                    "type": "tool_use",
                    "id": "toolu_001",
                    "name": "get_weather",
                    "input": {"city": "Beijing"}
                },
                {
                    "type": "tool_use",
                    "id": "toolu_002",
                    "name": "get_weather",
                    "input": {"city": "Shanghai"}
                }
            ]),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode multiple tool_uses");

    assert_eq!(payload["messages"][0]["tool_calls"].as_array().unwrap().len(), 2);
    assert_eq!(payload["messages"][0]["tool_calls"][0]["id"], "toolu_001");
    assert_eq!(payload["messages"][0]["tool_calls"][1]["id"], "toolu_002");
}

#[test]
fn skips_thinking_blocks() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "assistant".to_string(),
            content: json!([
                {"type": "thinking", "thinking": "Let me think about this..."},
                {"type": "text", "text": "Here is my answer."}
            ]),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode with thinking block");

    assert_eq!(payload["messages"][0]["role"], "assistant");
    assert_eq!(payload["messages"][0]["content"], "Here is my answer.");
    // thinking block should not appear
    assert!(payload["messages"][0].get("thinking").is_none());
}

#[test]
fn handles_tool_result_with_array_content() {
    let ir = IrRequest {
        source_protocol: "anthropic".to_string(),
        target_protocol: "openai".to_string(),
        model: Some("gpt-4o-mini".to_string()),
        system_parts: Vec::new(),
        messages: vec![ProtocolIrMessage {
            role: "user".to_string(),
            content: json!([
                {
                    "type": "tool_result",
                    "tool_use_id": "toolu_123",
                    "content": [
                        {"type": "text", "text": "Result part 1"},
                        {"type": "text", "text": "Result part 2"}
                    ]
                }
            ]),
        }],
        tools: Vec::new(),
        extensions: BTreeMap::new(),
        metadata: BTreeMap::new(),
    };

    let payload = encode_openai_chat_request(&ir).expect("encode tool_result with array content");

    // Tool result with array content is converted directly to tool message
    // No empty user message before it
    assert_eq!(payload["messages"][0]["role"], "tool");
    assert_eq!(payload["messages"][0]["content"], "Result part 1\nResult part 2");
}
