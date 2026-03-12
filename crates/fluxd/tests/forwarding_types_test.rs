use fluxd::forwarding::types::{ForwardObservation, UsageSnapshot};

#[test]
fn observation_and_usage_default_to_empty_optional_metrics() {
    let observation = ForwardObservation::new("req_1", "gw_1");
    let usage = UsageSnapshot::default();

    assert_eq!(observation.request_id, "req_1");
    assert_eq!(observation.gateway_id, "gw_1");
    assert_eq!(usage.input_tokens, None);
    assert_eq!(usage.output_tokens, None);
    assert_eq!(usage.cached_tokens, None);
}
