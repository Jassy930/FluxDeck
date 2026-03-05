use std::collections::HashMap;

use crate::protocol::error::FluxError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProtocolAdapterDescriptor {
    pub source: String,
    pub target: String,
}

#[derive(Debug, Clone)]
pub struct ProtocolRegistry {
    adapters: HashMap<(String, String), ProtocolAdapterDescriptor>,
}

impl ProtocolRegistry {
    pub fn new() -> Self {
        Self {
            adapters: HashMap::new(),
        }
    }

    pub fn register_adapter(&mut self, source: impl Into<String>, target: impl Into<String>) {
        let source = source.into();
        let target = target.into();
        let descriptor = ProtocolAdapterDescriptor {
            source: source.clone(),
            target: target.clone(),
        };
        self.adapters.insert((source, target), descriptor);
    }

    pub fn resolve(
        &self,
        source: &str,
        target: &str,
    ) -> Result<&ProtocolAdapterDescriptor, FluxError> {
        self.adapters
            .get(&(source.to_string(), target.to_string()))
            .ok_or_else(|| FluxError::CapabilityUnsupported {
                source: source.to_string(),
                target: target.to_string(),
            })
    }
}

impl Default for ProtocolRegistry {
    fn default() -> Self {
        let mut registry = Self::new();
        registry.register_adapter("anthropic", "openai");
        registry
    }
}
