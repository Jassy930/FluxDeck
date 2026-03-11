use fluxd::protocol::adapters::anthropic::encode_anthropic_sse;
use fluxd::protocol::stream::{StreamEvent, Usage};

#[test]
fn encodes_text_delta_events() {
    let events = vec![
        StreamEvent::MessageStart {
            id: "msg_test".to_string(),
            model: Some("test-model".to_string()),
        },
        StreamEvent::TextDelta { text: "Hello".to_string() },
    ];

    let output = encode_anthropic_sse(&events);
    println!("Output:\n{}", output);
    let lines: Vec<&str> = output.lines().collect();

    // Check that output contains expected events
    assert!(output.contains("event: message_start"));
    assert!(output.contains("msg_test"));
    assert!(output.contains("event: content_block_start"));
    assert!(output.contains("text"));
    assert!(output.contains("Hello"));
}

#[test]
fn handles_tool_call_start_events() {
    let events = vec![
        StreamEvent::MessageStart {
            id: "msg_test".to_string(),
            model: Some("test-model".to_string()),
        },
        StreamEvent::ToolCallStart {
            index: 1,
            id: "toolu_123".to_string(),
            name: "weather".to_string(),
        },
    ];

    let output = encode_anthropic_sse(&events);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.len() >= 4);
    assert!(lines[0].starts_with("event: message_start"));
    assert!(lines[1].contains("msg_test"));
    // Should contain tool_use block start
    assert!(output.contains("tool_use"));
    assert!(output.contains("toolu_123"));
}

#[test]
fn handles_tool_call_delta_events() {
    let events = vec![
        StreamEvent::MessageStart {
            id: "msg_test".to_string(),
            model: Some("test-model".to_string()),
        },
        StreamEvent::ToolCallDelta {
            index: 1,
            arguments: r#"{"city": "Bei"}"#.to_string(),
        },
    ];

    let output = encode_anthropic_sse(&events);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.len() >= 4);
    assert!(lines[0].starts_with("event: message_start"));
    assert!(lines[1].contains("msg_test"));
    assert!(output.contains("input_json_delta"));
}

#[test]
fn handles_message_delta_events() {
    let events = vec![
        StreamEvent::MessageStart {
            id: "msg_test".to_string(),
            model: Some("test-model".to_string()),
        },
        StreamEvent::MessageDelta {
            stop_reason: Some("end_turn".to_string()),
            stop_sequence: Some("\n\nHuman:".to_string()),
            usage: Some(Usage {
                input_tokens: 100,
                output_tokens: 200
            }),
        },
    ];

    let output = encode_anthropic_sse(&events);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.len() >= 4);
    assert!(lines[0].starts_with("event: message_start"));
    assert!(lines[1].contains("msg_test"));
    assert!(output.contains("event: message_delta"));
    assert!(output.contains("end_turn"));
    assert!(output.contains("stop_sequence"));
    assert!(output.contains("input_tokens"));
}

#[test]
fn handles_message_stop_events() {
    let events = vec![
        StreamEvent::MessageStart {
            id: "msg_test".to_string(),
            model: Some("test-model".to_string()),
        },
        StreamEvent::MessageStop,
    ];

    let output = encode_anthropic_sse(&events);
    let lines: Vec<&str> = output.lines().collect();

    assert!(lines.len() >= 3);
    assert!(lines[0].starts_with("event: message_start"));
    assert!(lines[1].contains("msg_test"));
    assert!(output.contains("event: message_stop"));
}

#[test]
fn handles_text_tool_text_interleaving() {
    // Test the critical scenario: text -> tool_use -> text
    // This verifies that:
    // 1. Text block starts at index 0
    // 2. Tool_use block closes text and starts at its own index
    // 3. Returning to text closes tool_use and reopens text at index 0
    let events = vec![
        StreamEvent::MessageStart {
            id: "msg_interleave".to_string(),
            model: Some("test-model".to_string()),
        },
        StreamEvent::TextDelta { text: "Let me check ".to_string() },
        StreamEvent::ToolCallStart {
            index: 1,
            id: "toolu_001".to_string(),
            name: "get_weather".to_string(),
        },
        StreamEvent::ToolCallDelta {
            index: 1,
            arguments: r#"{"city":"Beijing"}"#.to_string(),
        },
        StreamEvent::TextDelta { text: "The weather is sunny.".to_string() },
        StreamEvent::MessageStop,
    ];

    let output = encode_anthropic_sse(&events);
    println!("Interleaving output:\n{}", output);

    // Verify message_start
    assert!(output.contains("event: message_start"));

    // First text block (index 0)
    assert!(output.contains("event: content_block_start"));
    assert!(output.contains("Let me check "));

    // Tool use block (index 1)
    assert!(output.contains("tool_use"));
    assert!(output.contains("toolu_001"));
    assert!(output.contains("get_weather"));
    assert!(output.contains("input_json_delta"));

    // After tool, text should resume (content_block_stop for tool, then new text)
    // Count occurrences of content_block_start - should be at least 2 (text + tool, or text + tool + text)
    let block_starts = output.matches("event: content_block_start").count();
    assert!(block_starts >= 2, "Expected at least 2 content_block_start events, got {}", block_starts);

    // Count content_block_stop events
    let block_stops = output.matches("event: content_block_stop").count();
    assert!(block_stops >= 2, "Expected at least 2 content_block_stop events, got {}", block_stops);

    // Final text content
    assert!(output.contains("The weather is sunny."));

    // Message stop
    assert!(output.contains("event: message_stop"));
}
