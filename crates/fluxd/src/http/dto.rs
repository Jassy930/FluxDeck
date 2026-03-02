use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct BasicOk {
    pub ok: bool,
}

impl BasicOk {
    pub fn new() -> Self {
        Self { ok: true }
    }
}
