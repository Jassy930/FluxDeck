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

    func testRuntimeCategoryAndOverviewMetrics() {
        let providers = [
            AdminProvider(
                id: "provider_main",
                name: "Main Provider",
                kind: "openai",
                baseURL: "https://api.openai.com/v1",
                enabled: true
            )
        ]

        let gateways = [
            AdminGateway(
                id: "gw_running",
                name: "Running",
                listenHost: "127.0.0.1",
                listenPort: 18080,
                inboundProtocol: "openai",
                defaultProviderId: "provider_main",
                enabled: true,
                runtimeStatus: "running",
                lastError: nil
            ),
            AdminGateway(
                id: "gw_error",
                name: "Error",
                listenHost: "127.0.0.1",
                listenPort: 18081,
                inboundProtocol: "openai",
                defaultProviderId: "provider_main",
                enabled: true,
                runtimeStatus: "stopped",
                lastError: "upstream timeout"
            )
        ]

        XCTAssertEqual(runtimeCategory(for: gateways[0]), .running)
        XCTAssertEqual(runtimeCategory(for: gateways[1]), .error)

        let metrics = buildDashboardMetrics(providers: providers, gateways: gateways)
        XCTAssertEqual(metrics.providerCount, 1)
        XCTAssertEqual(metrics.gatewayCount, 2)
        XCTAssertEqual(metrics.runningGatewayCount, 1)
        XCTAssertEqual(metrics.errorGatewayCount, 1)
    }

    func testEncodesCreatePayloadWithSnakeCaseKeys() throws {
        let providerInput = CreateProviderInput(
            id: "provider_ui",
            name: "UI Provider",
            kind: "openai",
            baseURL: "https://api.openai.com/v1",
            apiKey: "sk-test",
            models: ["gpt-4o-mini"],
            enabled: true
        )
        let gatewayInput = CreateGatewayInput(
            id: "gateway_ui",
            name: "UI Gateway",
            listenHost: "127.0.0.1",
            listenPort: 18080,
            inboundProtocol: "openai",
            defaultProviderId: "provider_ui",
            defaultModel: "gpt-4o-mini",
            enabled: true
        )

        let providerData = try JSONEncoder().encode(providerInput)
        let gatewayData = try JSONEncoder().encode(gatewayInput)

        let providerJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: providerData) as? [String: Any]
        )
        let gatewayJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: gatewayData) as? [String: Any]
        )

        XCTAssertEqual(providerJSON["base_url"] as? String, "https://api.openai.com/v1")
        XCTAssertEqual(providerJSON["api_key"] as? String, "sk-test")
        XCTAssertEqual((providerJSON["models"] as? [String])?.first, "gpt-4o-mini")

        XCTAssertEqual(gatewayJSON["listen_host"] as? String, "127.0.0.1")
        XCTAssertEqual(gatewayJSON["listen_port"] as? Int, 18080)
        XCTAssertEqual(gatewayJSON["default_provider_id"] as? String, "provider_ui")
        XCTAssertEqual(gatewayJSON["default_model"] as? String, "gpt-4o-mini")
    }

    func testDecodesLogsPayload() throws {
        let logsData = """
        [
          {
            "request_id": "req_001",
            "gateway_id": "gateway_main",
            "provider_id": "provider_main",
            "model": "gpt-4o-mini",
            "status_code": 200,
            "latency_ms": 132,
            "error": null,
            "created_at": "2026-03-03T10:00:00Z"
          }
        ]
        """.data(using: .utf8)!

        let logs = try AdminApiClient.decodeLogs(from: logsData)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.requestID, "req_001")
        XCTAssertEqual(logs.first?.statusCode, 200)
    }

    func testFiltersLogsByGatewayProviderAndStatus() {
        let logs = [
            AdminLog(
                requestID: "req_ok",
                gatewayID: "gw_a",
                providerID: "pv_a",
                model: "gpt-4o-mini",
                statusCode: 200,
                latencyMs: 100,
                error: nil,
                createdAt: "2026-03-03T10:00:00Z"
            ),
            AdminLog(
                requestID: "req_err",
                gatewayID: "gw_b",
                providerID: "pv_b",
                model: nil,
                statusCode: 502,
                latencyMs: 2200,
                error: "bad gateway",
                createdAt: "2026-03-03T10:01:00Z"
            )
        ]

        let onlyGatewayA = filterLogs(logs, gatewayID: "gw_a", providerID: nil, statusCode: nil)
        XCTAssertEqual(onlyGatewayA.count, 1)
        XCTAssertEqual(onlyGatewayA.first?.requestID, "req_ok")

        let onlyStatus5xx = filterLogs(logs, gatewayID: nil, providerID: nil, statusCode: 502)
        XCTAssertEqual(onlyStatus5xx.count, 1)
        XCTAssertEqual(onlyStatus5xx.first?.requestID, "req_err")

        let combined = filterLogs(logs, gatewayID: "gw_b", providerID: "pv_b", statusCode: 502)
        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(combined.first?.requestID, "req_err")

        let errorsOnly = filterLogs(logs, gatewayID: nil, providerID: nil, statusCode: nil, errorsOnly: true)
        XCTAssertEqual(errorsOnly.count, 1)
        XCTAssertEqual(errorsOnly.first?.requestID, "req_err")
    }
}
