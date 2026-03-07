import XCTest
@testable import FluxDeckNative

final class FluxDeckNativeTests: XCTestCase {
    func testWorkbenchDerivedModelsStayConsistentForSharedFixture() {
        let providers = [
            AdminProvider(
                id: "pv",
                name: "Provider",
                kind: "openai",
                baseURL: "https://api.openai.com/v1",
                apiKey: "sk",
                models: ["gpt-4o-mini"],
                enabled: true
            )
        ]
        let gateways = [
            AdminGateway(
                id: "gw",
                name: "Gateway",
                listenHost: "127.0.0.1",
                listenPort: 18080,
                inboundProtocol: "openai",
                defaultProviderId: "pv",
                enabled: true,
                runtimeStatus: "running",
                lastError: nil
            )
        ]
        let logs = [
            AdminLog(
                requestID: "req_1",
                gatewayID: "gw",
                providerID: "pv",
                model: "gpt-4o-mini",
                statusCode: 200,
                latencyMs: 120,
                error: nil,
                createdAt: "2026-03-06T10:00:00Z"
            )
        ]

        XCTAssertEqual(
            OverviewDashboardModel.make(providers: providers, gateways: gateways, logs: logs).trafficSummary.totalRequestsText,
            "1"
        )
        XCTAssertEqual(
            TopologyGraph.make(gateways: gateways, providers: providers, logs: logs).edges.count,
            2
        )
        XCTAssertEqual(TrafficAnalyticsModel.make(logs: logs).totalRequests, 1)
    }

    func testLogsAndSettingsWorkbenchModelsBuildDetailCards() {
        let logCard = LogDetailCardModel.make(
            log: AdminLog(
                requestID: "req_1",
                gatewayID: "gw",
                providerID: "pv",
                model: "gpt-4o-mini",
                statusCode: 502,
                latencyMs: 800,
                error: "timeout",
                createdAt: "2026-03-06T10:00:00Z"
            )
        )
        let settings = SettingsPanelModel.make(
            adminBaseURL: "http://127.0.0.1:7777",
            isLoading: false,
            hasError: false
        )

        XCTAssertEqual(logCard.statusText, "502")
        XCTAssertEqual(logCard.errorText, "timeout")
        XCTAssertEqual(settings.sections.map(\.title), ["Admin API", "Refresh & Sync", "Diagnostics"])
    }

    func testResourceWorkspaceModelsExposePrimaryAndSecondaryMetadata() {
        let providerCard = ProviderWorkspaceCard.make(
            provider: AdminProvider(
                id: "pv",
                name: "Provider",
                kind: "openai",
                baseURL: "https://api.openai.com/v1",
                apiKey: "sk",
                models: ["gpt-4o-mini", "gpt-4.1-mini"],
                enabled: true
            )
        )
        let gatewayCard = GatewayWorkspaceCard.make(
            gateway: AdminGateway(
                id: "gw",
                name: "Gateway",
                listenHost: "127.0.0.1",
                listenPort: 18080,
                inboundProtocol: "openai",
                defaultProviderId: "pv",
                enabled: true,
                runtimeStatus: "running",
                lastError: nil
            )
        )

        XCTAssertEqual(providerCard.modelCountText, "2 models")
        XCTAssertEqual(gatewayCard.endpointText, "127.0.0.1:18080")
        XCTAssertEqual(gatewayCard.runtimeBadge, "RUNNING")
    }

    func testTrafficAndConnectionsModelsAggregateLogs() {
        let logs = [
            AdminLog(
                requestID: "req_ok",
                gatewayID: "gw_a",
                providerID: "pv_a",
                model: "gpt-4o-mini",
                statusCode: 200,
                latencyMs: 100,
                error: nil,
                createdAt: "2026-03-06T10:00:00Z"
            ),
            AdminLog(
                requestID: "req_err",
                gatewayID: "gw_b",
                providerID: "pv_b",
                model: "claude-3-7-sonnet",
                statusCode: 500,
                latencyMs: 900,
                error: "timeout",
                createdAt: "2026-03-06T10:01:00Z"
            )
        ]

        let traffic = TrafficAnalyticsModel.make(logs: logs)
        let connections = ConnectionsModel.make(logs: logs)

        XCTAssertEqual(traffic.totalRequests, 2)
        XCTAssertEqual(traffic.errorCount, 1)
        XCTAssertEqual(connections.activeGatewayIDs.sorted(), ["gw_a", "gw_b"])
    }

    func testTopologyGraphBuildsGatewayProviderEdgesFromLogs() {
        let graph = TopologyGraph.make(
            gateways: [
                AdminGateway(
                    id: "gw",
                    name: "Gateway",
                    listenHost: "127.0.0.1",
                    listenPort: 18080,
                    inboundProtocol: "openai",
                    defaultProviderId: "pv",
                    enabled: true,
                    runtimeStatus: "running",
                    lastError: nil
                )
            ],
            providers: [
                AdminProvider(
                    id: "pv",
                    name: "Provider",
                    kind: "openai",
                    baseURL: "https://api.openai.com/v1",
                    apiKey: "sk",
                    models: ["gpt-4o-mini"],
                    enabled: true
                )
            ],
            logs: [
                AdminLog(
                    requestID: "req_1",
                    gatewayID: "gw",
                    providerID: "pv",
                    model: "gpt-4o-mini",
                    statusCode: 200,
                    latencyMs: 120,
                    error: nil,
                    createdAt: "2026-03-06T10:00:00Z"
                ),
                AdminLog(
                    requestID: "req_2",
                    gatewayID: "gw",
                    providerID: "pv",
                    model: "gpt-4o-mini",
                    statusCode: 502,
                    latencyMs: 800,
                    error: "bad gateway",
                    createdAt: "2026-03-06T10:01:00Z"
                )
            ]
        )

        XCTAssertEqual(graph.columns.count, 3)
        XCTAssertEqual(graph.edges.count, 2)
        XCTAssertEqual(graph.edges.first?.requestCount, 2)
    }

    func testOverviewDashboardModelBuildsRunningAndTrafficCards() {
        let model = OverviewDashboardModel.make(
            providers: [
                AdminProvider(
                    id: "pv",
                    name: "Provider",
                    kind: "openai",
                    baseURL: "https://api.openai.com/v1",
                    apiKey: "sk",
                    models: ["gpt-4o-mini"],
                    enabled: true
                )
            ],
            gateways: [
                AdminGateway(
                    id: "gw",
                    name: "Gateway",
                    listenHost: "127.0.0.1",
                    listenPort: 18080,
                    inboundProtocol: "openai",
                    defaultProviderId: "pv",
                    enabled: true,
                    runtimeStatus: "running",
                    lastError: nil
                )
            ],
            logs: [
                AdminLog(
                    requestID: "req_1",
                    gatewayID: "gw",
                    providerID: "pv",
                    model: "gpt-4o-mini",
                    statusCode: 200,
                    latencyMs: 120,
                    error: nil,
                    createdAt: "2026-03-06T10:00:00Z"
                )
            ]
        )

        XCTAssertEqual(model.runningStatus.connectionCountText, "1")
        XCTAssertEqual(model.networkStatus.internetLatencyText, "120 ms")
        XCTAssertEqual(model.trafficSummary.totalRequestsText, "1")
    }

    func testShellStatusSummaryUsesGatewayAndErrorCounts() {
        let summary = ShellStatusSummary.make(
            isLoading: false,
            loadError: "gateway timeout",
            gateways: [
                AdminGateway(
                    id: "gw",
                    name: "GW",
                    listenHost: "127.0.0.1",
                    listenPort: 18080,
                    inboundProtocol: "openai",
                    defaultProviderId: "pv",
                    enabled: true,
                    runtimeStatus: "running",
                    lastError: nil
                )
            ]
        )

        XCTAssertEqual(summary.connectionLabel, "Connected")
        XCTAssertEqual(summary.errorLabel, "1 alert")
    }

    func testDesignTokensExposeDarkWorkbenchPalette() {
        XCTAssertEqual(DesignTokens.cornerRadius.window, 26)
        XCTAssertEqual(DesignTokens.cornerRadius.card, 18)
        XCTAssertEqual(DesignTokens.statusColors.running.accessibilityName, "running")
        XCTAssertEqual(DesignTokens.statusColors.error.accessibilityName, "error")
    }

    func testNavigationGroupsExposeExpectedSections() {
        let groups = SidebarGroup.defaultGroups

        XCTAssertEqual(groups.map(\.title), ["Overview", "Visualization", "Proxy", "System"])
        XCTAssertTrue(groups[1].items.contains(.topology))
        XCTAssertTrue(groups[2].items.contains(.providers))
        XCTAssertEqual(AppMode.allCases.map(\.rawValue), ["Backup", "Direct", "Rule", "Global"])
    }

    func testDecodesProvidersAndGatewaysPayload() throws {
        let providersData = """
        [
          {
            "id": "provider_main",
            "name": "Main Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-main",
            "models": ["gpt-4o-mini"],
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
        XCTAssertEqual(providers.first?.apiKey, "sk-main")
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
                apiKey: "sk-test-main",
                models: ["gpt-4o-mini"],
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
        let updateProviderInput = UpdateProviderInput(
            name: "UI Provider Updated",
            kind: "openai",
            baseURL: "https://api.openai.com/v1",
            apiKey: "sk-test-updated",
            models: ["gpt-4.1-mini"],
            enabled: false
        )

        let providerData = try JSONEncoder().encode(providerInput)
        let gatewayData = try JSONEncoder().encode(gatewayInput)
        let updateProviderData = try JSONEncoder().encode(updateProviderInput)

        let providerJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: providerData) as? [String: Any]
        )
        let gatewayJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: gatewayData) as? [String: Any]
        )
        let updateProviderJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: updateProviderData) as? [String: Any]
        )

        XCTAssertEqual(providerJSON["base_url"] as? String, "https://api.openai.com/v1")
        XCTAssertEqual(providerJSON["api_key"] as? String, "sk-test")
        XCTAssertEqual((providerJSON["models"] as? [String])?.first, "gpt-4o-mini")

        XCTAssertEqual(gatewayJSON["listen_host"] as? String, "127.0.0.1")
        XCTAssertEqual(gatewayJSON["listen_port"] as? Int, 18080)
        XCTAssertEqual(gatewayJSON["default_provider_id"] as? String, "provider_ui")
        XCTAssertEqual(gatewayJSON["default_model"] as? String, "gpt-4o-mini")

        XCTAssertEqual(updateProviderJSON["base_url"] as? String, "https://api.openai.com/v1")
        XCTAssertEqual(updateProviderJSON["api_key"] as? String, "sk-test-updated")
        XCTAssertEqual((updateProviderJSON["models"] as? [String])?.first, "gpt-4.1-mini")
        XCTAssertEqual(updateProviderJSON["enabled"] as? Bool, false)
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

    func testRecentLogsReturnsLatestTenEntriesInDescendingOrder() {
        let logs = (1...12).map { index in
            AdminLog(
                requestID: String(format: "req_%03d", index),
                gatewayID: "gw",
                providerID: "pv",
                model: nil,
                statusCode: 200,
                latencyMs: 100,
                error: nil,
                createdAt: String(format: "2026-03-03T10:%02d:00Z", index)
            )
        }

        let recent = recentLogs(logs, limit: 10)

        XCTAssertEqual(recent.count, 10)
        XCTAssertEqual(recent.first?.requestID, "req_012")
        XCTAssertEqual(recent.last?.requestID, "req_003")
    }

    func testNormalizedAdminBaseURL() {
        XCTAssertEqual(
            normalizedAdminBaseURL("127.0.0.1:7777")?.absoluteString,
            "http://127.0.0.1:7777"
        )
        XCTAssertEqual(
            normalizedAdminBaseURL("https://example.com/admin")?.absoluteString,
            "https://example.com/admin"
        )
        XCTAssertNil(normalizedAdminBaseURL("ftp://example.com"))
        XCTAssertNil(normalizedAdminBaseURL("not a url"))
    }
}
