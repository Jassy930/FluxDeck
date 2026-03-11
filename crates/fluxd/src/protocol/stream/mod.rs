#[derive(Debug, Clone, PartialEq)]
pub struct Usage {
    pub input_tokens: u64,
    pub output_tokens: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum StreamEvent {
    MessageStart {
        id: String,
        model: Option<String>,
    },
    TextDelta {
        text: String,
    },
    ToolCallStart {
        index: usize,
        id: String,
        name: String,
    },
    ToolCallDelta {
        index: usize,
        arguments: String,
    },
    MessageDelta {
        stop_reason: Option<String>,
        stop_sequence: Option<String>,
        usage: Option<Usage>,
    },
    MessageStop,
}
