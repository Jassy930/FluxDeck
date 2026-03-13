use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(name = "fluxctl")]
pub struct Cli {
    #[arg(long, default_value = "http://127.0.0.1:7777")]
    pub admin_url: String,

    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Debug, Subcommand)]
pub enum Commands {
    Provider {
        #[command(subcommand)]
        command: ProviderCmd,
    },
    Gateway {
        #[command(subcommand)]
        command: GatewayCmd,
    },
    Logs {
        #[arg(long, default_value_t = 50)]
        limit: usize,
    },
}

#[derive(Debug, Subcommand)]
pub enum ProviderCmd {
    Create {
        #[arg(long)]
        id: String,
        #[arg(long)]
        name: String,
        #[arg(long)]
        kind: String,
        #[arg(long = "base-url")]
        base_url: String,
        #[arg(long = "api-key")]
        api_key: String,
        #[arg(long)]
        models: String,
        #[arg(long, action = clap::ArgAction::Set, default_value_t = true)]
        enabled: bool,
    },
    Delete {
        id: String,
        #[arg(short = 'y', long = "yes", default_value_t = false)]
        yes: bool,
    },
    Probe {
        id: String,
    },
    Health {
        #[command(subcommand)]
        command: ProviderHealthCmd,
    },
    List,
}

#[derive(Debug, Subcommand)]
pub enum ProviderHealthCmd {
    List,
}

#[derive(Debug, Subcommand)]
pub enum GatewayCmd {
    Create {
        #[arg(long)]
        id: String,
        #[arg(long)]
        name: String,
        #[arg(long = "listen-host", default_value = "127.0.0.1")]
        listen_host: String,
        #[arg(long = "listen-port")]
        listen_port: i64,
        #[arg(long = "inbound-protocol", default_value = "openai")]
        inbound_protocol: String,
        #[arg(long = "upstream-protocol", default_value = "provider_default")]
        upstream_protocol: String,
        #[arg(long = "protocol-config-json", default_value = "{}")]
        protocol_config_json: String,
        #[arg(long = "default-provider-id")]
        default_provider_id: String,
        #[arg(long = "route-target")]
        route_targets: Vec<String>,
        #[arg(long = "default-model")]
        default_model: Option<String>,
        #[arg(long, action = clap::ArgAction::Set, default_value_t = true)]
        enabled: bool,
        #[arg(long = "auto-start", action = clap::ArgAction::Set, default_value_t = false)]
        auto_start: bool,
    },
    Update {
        id: String,
        #[arg(long)]
        name: String,
        #[arg(long = "listen-host", default_value = "127.0.0.1")]
        listen_host: String,
        #[arg(long = "listen-port")]
        listen_port: i64,
        #[arg(long = "inbound-protocol", default_value = "openai")]
        inbound_protocol: String,
        #[arg(long = "upstream-protocol", default_value = "provider_default")]
        upstream_protocol: String,
        #[arg(long = "protocol-config-json", default_value = "{}")]
        protocol_config_json: String,
        #[arg(long = "default-provider-id")]
        default_provider_id: String,
        #[arg(long = "route-target")]
        route_targets: Vec<String>,
        #[arg(long = "default-model")]
        default_model: Option<String>,
        #[arg(long, action = clap::ArgAction::Set, default_value_t = true)]
        enabled: bool,
        #[arg(long = "auto-start", action = clap::ArgAction::Set, default_value_t = false)]
        auto_start: bool,
    },
    Delete {
        id: String,
        #[arg(short = 'y', long = "yes", default_value_t = false)]
        yes: bool,
    },
    List,
    Start {
        id: String,
    },
    Stop {
        id: String,
    },
}
