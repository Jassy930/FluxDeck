use serde_json::Value;

use crate::protocol::ir::IrRequest;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CountResult {
    pub input_tokens: u64,
    pub estimated: bool,
}

pub fn count_tokens(ir: &IrRequest, upstream_input_tokens: Option<u64>) -> CountResult {
    match upstream_input_tokens {
        Some(input_tokens) => CountResult {
            input_tokens,
            estimated: false,
        },
        None => CountResult {
            input_tokens: estimate_tokens(ir),
            estimated: true,
        },
    }
}

pub fn estimate_tokens(ir: &IrRequest) -> u64 {
    let mut units = 0_u64;

    if let Some(model) = &ir.model {
        units += model.len() as u64;
    }

    for part in &ir.system_parts {
        units += estimate_value_units(part);
    }

    for message in &ir.messages {
        units += message.role.len() as u64;
        units += estimate_value_units(&message.content);
    }

    for tool in &ir.tools {
        units += estimate_value_units(tool);
    }

    for extension in ir.extensions.values() {
        units += estimate_value_units(extension);
    }

    ((units + 3) / 4).max(1)
}

fn estimate_value_units(value: &Value) -> u64 {
    match value {
        Value::Null => 0,
        Value::Bool(flag) => {
            if *flag {
                4
            } else {
                5
            }
        }
        Value::Number(number) => number.to_string().len() as u64,
        Value::String(text) => text.len() as u64,
        Value::Array(items) => items.iter().map(estimate_value_units).sum(),
        Value::Object(map) => map
            .iter()
            .map(|(key, item)| key.len() as u64 + estimate_value_units(item))
            .sum(),
    }
}
