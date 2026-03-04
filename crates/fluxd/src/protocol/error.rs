use std::error::Error;
use std::fmt::{Display, Formatter};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecodeErrorKind {
    InvalidPayload,
    MissingRequiredField { field: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FluxError {
    CapabilityUnsupported { source: String, target: String },
    DecodeError {
        protocol: String,
        kind: DecodeErrorKind,
    },
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
            Self::DecodeError { protocol, kind } => match kind {
                DecodeErrorKind::InvalidPayload => {
                    write!(f, "decode error for {protocol}: payload must be a JSON object")
                }
                DecodeErrorKind::MissingRequiredField { field } => {
                    write!(
                        f,
                        "decode error for {protocol}: missing required field `{field}`"
                    )
                }
            },
        }
    }
}

impl Error for FluxError {}
