use fluxd::protocol::adapters::anthropic::decode_anthropic_request;
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
        ]
    });

    let ir = decode_anthropic_request(&payload).expect("decode anthropic request");
    assert_eq!(ir.model.as_deref(), Some("claude-3-7-sonnet"));
    assert_eq!(ir.system_parts.len(), 1);
    assert_eq!(ir.tools.len(), 1);
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
    assert!(result.is_err());
}
