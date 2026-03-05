use fluxd::protocol::registry::ProtocolRegistry;

#[test]
fn default_registry_resolves_anthropic_to_openai() {
    let registry = ProtocolRegistry::default();
    assert!(registry.resolve("anthropic", "openai").is_ok());
}
