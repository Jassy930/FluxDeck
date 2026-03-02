use clap::Parser;
use fluxctl::cli::{Cli, Commands, ProviderCmd};

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
