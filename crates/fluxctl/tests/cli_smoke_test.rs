use clap::Parser;
use fluxctl::cli::{Cli, Commands, GatewayCmd, ProviderCmd};

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
    ]);

    match cli.command {
        Commands::Gateway { command } => match command {
            GatewayCmd::Create {
                inbound_protocol,
                upstream_protocol,
                protocol_config_json,
                ..
            } => {
                assert_eq!(inbound_protocol, "anthropic");
                assert_eq!(upstream_protocol, "openai");
                assert_eq!(protocol_config_json, "{\"compatibility_mode\":\"compatible\"}");
            }
            _ => panic!("expected gateway create command"),
        },
        _ => panic!("expected gateway command"),
    }
}
