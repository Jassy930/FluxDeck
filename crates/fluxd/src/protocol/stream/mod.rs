#[derive(Debug, Clone, PartialEq)]
pub enum StreamEvent {
    MessageStart {
        id: String,
        model: Option<String>,
    },
    TextDelta {
        text: String,
    },
    MessageStop,
}
