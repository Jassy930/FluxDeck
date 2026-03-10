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
    MessageStop,
}
