use clap::Parser;
use fluxctl::cli::{Cli, Commands, GatewayCmd, ProviderCmd};
use fluxctl::build_logs_path;

#[test]
fn parses_provider_create_command() {
    let cli = Cli::parse_from([
        "fluxctl",
        "--admin-url",
        "http://127.0.0.1:7777",
        "provider",
        "create",
        "--id",
        "provider_1",
        "--name",
        "Main",
        "--kind",
        "openai",
        "--base-url",
        "https://api.openai.com/v1",
        "--api-key",
        "sk-test",
        "--models",
        "gpt-4o-mini,gpt-4.1",
    ]);

    assert_eq!(cli.admin_url, "http://127.0.0.1:7777");

    match cli.command {
        Commands::Provider { command } => match command {
            ProviderCmd::Create { id, name, .. } => {
                assert_eq!(id, "provider_1");
                assert_eq!(name, "Main");
            }
            _ => panic!("expected provider create command"),
        },
        _ => panic!("expected provider command"),
    }
}

#[test]
fn parses_provider_delete_command_with_yes_flag() {
    let cli = Cli::parse_from([
        "fluxctl",
        "provider",
        "delete",
        "provider_1",
        "--yes",
    ]);

    match cli.command {
        Commands::Provider { command } => match command {
            ProviderCmd::Delete { id, yes } => {
                assert_eq!(id, "provider_1");
                assert!(yes);
            }
            _ => panic!("expected provider delete command"),
        },
        _ => panic!("expected provider command"),
    }
}

#[test]
fn parses_gateway_create_with_protocol_graph_fields() {
    let cli = Cli::parse_from([
        "fluxctl",
        "--admin-url",
        "http://127.0.0.1:7777",
        "gateway",
        "create",
        "--id",
        "gateway_1",
        "--name",
        "Gateway 1",
        "--listen-port",
        "18080",
        "--inbound-protocol",
        "anthropic",
        "--upstream-protocol",
        "openai",
        "--protocol-config-json",
        "{\"compatibility_mode\":\"compatible\"}",
        "--default-provider-id",
        "provider_1",
        "--default-model",
        "claude-3-7-sonnet",
        "--auto-start",
        "true",
    ]);

    match cli.command {
        Commands::Gateway { command } => match command {
            GatewayCmd::Create {
                inbound_protocol,
                upstream_protocol,
                protocol_config_json,
                auto_start,
                ..
            } => {
                assert_eq!(inbound_protocol, "anthropic");
                assert_eq!(upstream_protocol, "openai");
                assert_eq!(protocol_config_json, "{\"compatibility_mode\":\"compatible\"}");
                assert!(auto_start);
            }
            _ => panic!("expected gateway create command"),
        },
        _ => panic!("expected gateway command"),
    }
}

#[test]
fn parses_gateway_update_command() {
    let cli = Cli::parse_from([
        "fluxctl",
        "--admin-url",
        "http://127.0.0.1:7777",
        "gateway",
        "update",
        "gateway_1",
        "--name",
        "Gateway Updated",
        "--listen-host",
        "127.0.0.1",
        "--listen-port",
        "19090",
        "--inbound-protocol",
        "openai",
        "--upstream-protocol",
        "provider_default",
        "--protocol-config-json",
        "{\"compatibility_mode\":\"strict\"}",
        "--default-provider-id",
        "provider_1",
        "--default-model",
        "gpt-4.1-mini",
        "--enabled",
        "false",
        "--auto-start",
        "true",
    ]);

    match cli.command {
        Commands::Gateway { command } => match command {
            GatewayCmd::Update {
                id,
                listen_port,
                protocol_config_json,
                enabled,
                auto_start,
                ..
            } => {
                assert_eq!(id, "gateway_1");
                assert_eq!(listen_port, 19090);
                assert_eq!(protocol_config_json, "{\"compatibility_mode\":\"strict\"}");
                assert!(!enabled);
                assert!(auto_start);
            }
            _ => panic!("expected gateway update command"),
        },
        _ => panic!("expected gateway command"),
    }
}

#[test]
fn parses_gateway_delete_command_without_yes_flag() {
    let cli = Cli::parse_from([
        "fluxctl",
        "gateway",
        "delete",
        "gateway_1",
    ]);

    match cli.command {
        Commands::Gateway { command } => match command {
            GatewayCmd::Delete { id, yes } => {
                assert_eq!(id, "gateway_1");
                assert!(!yes);
            }
            _ => panic!("expected gateway delete command"),
        },
        _ => panic!("expected gateway command"),
    }
}


#[test]
fn builds_logs_path_with_limit_query() {
    assert_eq!(build_logs_path(20), "/admin/logs?limit=20");
}
