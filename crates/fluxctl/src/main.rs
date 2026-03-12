use std::io::{self, Write};

use anyhow::{anyhow, Result};
use clap::Parser;
use serde_json::json;

use fluxctl::build_logs_path;
use fluxctl::cli::{Cli, Commands, GatewayCmd, ProviderCmd};
use fluxctl::client::AdminClient;

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
            ProviderCmd::Delete { id, yes } => {
                if !confirm_delete(
                    "provider",
                    &id,
                    yes,
                    "若仍被 Gateway 引用，服务端会拒绝删除。",
                )? {
                    return Ok(());
                }

                let path = format!("/admin/providers/{id}");
                let result = client.delete_json(&path).await?;
                if result.get("ok").and_then(serde_json::Value::as_bool) == Some(true) {
                    println!("{}", serde_json::to_string_pretty(&result)?);
                } else {
                    return Err(anyhow!(serde_json::to_string_pretty(&result)?));
                }
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
            GatewayCmd::Delete { id, yes } => {
                if !confirm_delete(
                    "gateway",
                    &id,
                    yes,
                    "若实例正在运行，服务端会先停止再删除。",
                )? {
                    return Ok(());
                }

                let path = format!("/admin/gateways/{id}");
                let result = client.delete_json(&path).await?;
                if result.get("ok").and_then(serde_json::Value::as_bool) == Some(true) {
                    println!("{}", serde_json::to_string_pretty(&result)?);
                    if let Some(notice) = gateway_update_notice(&result) {
                        eprintln!("Notice: {notice}");
                    }
                } else {
                    return Err(anyhow!(serde_json::to_string_pretty(&result)?));
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
    result
        .get("user_notice")
        .and_then(serde_json::Value::as_str)
}

fn confirm_delete(resource_kind: &str, id: &str, yes: bool, detail: &str) -> Result<bool> {
    if yes {
        return Ok(true);
    }

    eprintln!("About to delete {resource_kind} `{id}`.");
    eprintln!("{detail}");
    eprint!("Continue? [y/N]: ");
    io::stderr().flush()?;

    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    if is_delete_confirmation_accepted(&input) {
        Ok(true)
    } else {
        eprintln!("Delete cancelled.");
        Ok(false)
    }
}

fn is_delete_confirmation_accepted(input: &str) -> bool {
    matches!(input.trim().to_ascii_lowercase().as_str(), "y" | "yes")
}

#[cfg(test)]
mod tests {
    use super::{gateway_update_notice, is_delete_confirmation_accepted};
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

    #[test]
    fn accepts_delete_confirmation_for_yes_variants() {
        assert!(is_delete_confirmation_accepted("y"));
        assert!(is_delete_confirmation_accepted("Y"));
        assert!(is_delete_confirmation_accepted("yes"));
        assert!(is_delete_confirmation_accepted(" YES "));
    }

    #[test]
    fn rejects_delete_confirmation_for_other_inputs() {
        assert!(!is_delete_confirmation_accepted(""));
        assert!(!is_delete_confirmation_accepted("n"));
        assert!(!is_delete_confirmation_accepted("delete"));
    }
}
