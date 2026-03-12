use anyhow::Result;
use clap::Parser;
use serde_json::json;

use fluxctl::cli::{Cli, Commands, GatewayCmd, ProviderCmd};
use fluxctl::client::AdminClient;
use fluxctl::build_logs_path;

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let client = AdminClient::new(cli.admin_url);

    match cli.command {
        Commands::Provider { command } => match command {
            ProviderCmd::Create {
                id,
                name,
                kind,
                base_url,
                api_key,
                models,
                enabled,
            } => {
                let payload = json!({
                    "id": id,
                    "name": name,
                    "kind": kind,
                    "base_url": base_url,
                    "api_key": api_key,
                    "models": split_models(&models),
                    "enabled": enabled
                });
                let result = client.post_json("/admin/providers", payload).await?;
                println!("{}", serde_json::to_string_pretty(&result)?);
            }
            ProviderCmd::List => {
                let result = client.get_json("/admin/providers").await?;
                println!("{}", serde_json::to_string_pretty(&result)?);
            }
        },
        Commands::Gateway { command } => match command {
            GatewayCmd::Create {
                id,
                name,
                listen_host,
                listen_port,
                inbound_protocol,
                upstream_protocol,
                protocol_config_json,
                default_provider_id,
                default_model,
                enabled,
                auto_start,
            } => {
                let protocol_config_json: serde_json::Value =
                    serde_json::from_str(&protocol_config_json)?;
                let payload = json!({
                    "id": id,
                    "name": name,
                    "listen_host": listen_host,
                    "listen_port": listen_port,
                    "inbound_protocol": inbound_protocol,
                    "upstream_protocol": upstream_protocol,
                    "protocol_config_json": protocol_config_json,
                    "default_provider_id": default_provider_id,
                    "default_model": default_model,
                    "enabled": enabled,
                    "auto_start": auto_start
                });
                let result = client.post_json("/admin/gateways", payload).await?;
                println!("{}", serde_json::to_string_pretty(&result)?);
            }
            GatewayCmd::Update {
                id,
                name,
                listen_host,
                listen_port,
                inbound_protocol,
                upstream_protocol,
                protocol_config_json,
                default_provider_id,
                default_model,
                enabled,
                auto_start,
            } => {
                let protocol_config_json: serde_json::Value =
                    serde_json::from_str(&protocol_config_json)?;
                let payload = json!({
                    "name": name,
                    "listen_host": listen_host,
                    "listen_port": listen_port,
                    "inbound_protocol": inbound_protocol,
                    "upstream_protocol": upstream_protocol,
                    "protocol_config_json": protocol_config_json,
                    "default_provider_id": default_provider_id,
                    "default_model": default_model,
                    "enabled": enabled,
                    "auto_start": auto_start
                });
                let path = format!("/admin/gateways/{id}");
                let result = client.put_json(&path, payload).await?;
                println!("{}", serde_json::to_string_pretty(&result)?);
                if let Some(notice) = gateway_update_notice(&result) {
                    eprintln!("Notice: {notice}");
                }
            }
            GatewayCmd::List => {
                let result = client.get_json("/admin/gateways").await?;
                println!("{}", serde_json::to_string_pretty(&result)?);
            }
            GatewayCmd::Start { id } => {
                let path = format!("/admin/gateways/{id}/start");
                let result = client.post_json(&path, json!({})).await?;
                println!("{}", serde_json::to_string_pretty(&result)?);
            }
            GatewayCmd::Stop { id } => {
                let path = format!("/admin/gateways/{id}/stop");
                let result = client.post_json(&path, json!({})).await?;
                println!("{}", serde_json::to_string_pretty(&result)?);
            }
        },
        Commands::Logs { limit } => {
            let result = client.get_json(&build_logs_path(limit)).await?;
            println!("{}", serde_json::to_string_pretty(&result)?);
        }
    }

    Ok(())
}

fn split_models(models: &str) -> Vec<String> {
    models
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn gateway_update_notice(result: &serde_json::Value) -> Option<&str> {
    result.get("user_notice").and_then(serde_json::Value::as_str)
}

#[cfg(test)]
mod tests {
    use super::gateway_update_notice;
    use serde_json::json;

    #[test]
    fn extracts_gateway_update_notice_from_result() {
        let value = json!({
            "gateway": {"id": "gw_1"},
            "restart_performed": true,
            "config_changed": true,
            "user_notice": "Gateway 配置已保存，运行中的实例已自动重启。"
        });

        assert_eq!(
            gateway_update_notice(&value),
            Some("Gateway 配置已保存，运行中的实例已自动重启。")
        );
    }

    #[test]
    fn returns_none_when_gateway_update_notice_missing() {
        let value = json!({
            "gateway": {"id": "gw_1"},
            "restart_performed": false,
            "config_changed": false
        });

        assert_eq!(gateway_update_notice(&value), None);
    }
}
