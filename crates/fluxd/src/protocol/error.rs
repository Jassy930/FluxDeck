use std::error::Error;
use std::fmt::{Display, Formatter};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FluxError {
    CapabilityUnsupported { source: String, target: String },
}

impl Display for FluxError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::CapabilityUnsupported { source, target } => {
                write!(
                    f,
                    "protocol capability is not supported: {source} -> {target}"
                )
            }
        }
    }
}

impl Error for FluxError {}
