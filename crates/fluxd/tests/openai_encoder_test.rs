use std::collections::BTreeMap;

use fluxd::protocol::adapters::openai::encode_openai_chat_request;
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
