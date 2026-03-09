pub mod cli;
pub mod client;

pub fn build_logs_path(limit: usize) -> String {
    format!("/admin/logs?limit={limit}")
}
