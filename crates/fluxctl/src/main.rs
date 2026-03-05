use anyhow::Result;
use clap::Parser;
use serde_json::json;

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
                    "enabled": enabled
                });
                let result = client.post_json("/admin/gateways", payload).await?;
                println!("{}", serde_json::to_string_pretty(&result)?);
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
        Commands::Logs { .. } => {
            let result = client.get_json("/admin/logs").await?;
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
