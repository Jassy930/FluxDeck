import XCTest
@testable import FluxDeckNative

final class FluxDeckNativeTests: XCTestCase {
    func testDecodesProvidersAndGatewaysPayload() throws {
        let providersData = """
        [
          {
            "id": "provider_main",
            "name": "Main Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "enabled": true
          }
        ]
        """.data(using: .utf8)!

        let gatewaysData = """
        [
          {
            "id": "gateway_main",
            "name": "Gateway Main",
            "listen_host": "127.0.0.1",
            "listen_port": 18080,
            "inbound_protocol": "openai",
            "default_provider_id": "provider_main",
            "enabled": true
          }
        ]
        """.data(using: .utf8)!

        let providers = try AdminApiClient.decodeProviders(from: providersData)
        let gateways = try AdminApiClient.decodeGateways(from: gatewaysData)

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.id, "provider_main")
        XCTAssertEqual(gateways.count, 1)
        XCTAssertEqual(gateways.first?.defaultProviderId, "provider_main")
    }
}
