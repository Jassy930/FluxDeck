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
                autoStart: true,
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
                autoStart: true,
                runtimeStatus: "running",
                lastError: nil
            )
        )

        XCTAssertEqual(providerCard.modelCountText, "2 models")
        XCTAssertEqual(gatewayCard.endpointText, "127.0.0.1:18080")
        XCTAssertEqual(gatewayCard.runtimeBadge, "RUNNING")
        XCTAssertEqual(gatewayCard.autoStartText, "ON")
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
                    autoStart: true,
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
                    autoStart: true,
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
                    autoStart: true,
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
            "enabled": true,
            "auto_start": true
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
        XCTAssertEqual(gateways.first?.autoStart, true)
    }

    func testDecodesGatewayUpdateResultPayload() throws {
        let updateData = """
        {
          "gateway": {
            "id": "gateway_main",
            "name": "Gateway Main",
            "listen_host": "0.0.0.0",
            "listen_port": 18080,
            "inbound_protocol": "openai",
            "upstream_protocol": "provider_default",
            "protocol_config_json": {},
            "default_provider_id": "provider_main",
            "default_model": "gpt-4o-mini",
            "enabled": true,
            "auto_start": true,
            "runtime_status": "running",
            "last_error": null
          },
          "runtime_status": "running",
          "last_error": null,
          "restart_performed": true,
          "config_changed": true,
          "user_notice": "Gateway 配置已保存，运行中的实例已自动重启。"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(AdminGatewayUpdateResult.self, from: updateData)

        XCTAssertEqual(result.gateway.id, "gateway_main")
        XCTAssertEqual(result.gateway.listenHost, "0.0.0.0")
        XCTAssertEqual(result.runtimeStatus, "running")
        XCTAssertEqual(result.restartPerformed, true)
        XCTAssertEqual(result.configChanged, true)
        XCTAssertEqual(result.userNotice, "Gateway 配置已保存，运行中的实例已自动重启。")
    }

    func testGatewayUpdateNoticeTextPrefersServerNoticeAndFallsBackLocally() {
        let gateway = AdminGateway(
            id: "gw_update",
            name: "Gateway Update",
            listenHost: "127.0.0.1",
            listenPort: 18080,
            inboundProtocol: "openai",
            defaultProviderId: "provider_main",
            enabled: true,
            autoStart: true,
            runtimeStatus: "running",
            lastError: nil
        )

        let serverNotice = AdminGatewayUpdateResult(
            gateway: gateway,
            runtimeStatus: "running",
            lastError: nil,
            restartPerformed: true,
            configChanged: true,
            userNotice: "Gateway 配置已保存，运行中的实例已自动重启。"
        )
        XCTAssertEqual(
            gatewayUpdateNoticeText(for: serverNotice),
            "Gateway 配置已保存，运行中的实例已自动重启。"
        )

        let failedRestart = AdminGatewayUpdateResult(
            gateway: gateway,
            runtimeStatus: "stopped",
            lastError: "address already in use",
            restartPerformed: true,
            configChanged: true,
            userNotice: nil
        )
        XCTAssertEqual(
            gatewayUpdateNoticeText(for: failedRestart),
            "Gateway 配置已保存，但自动重启失败：address already in use"
        )

        let unchanged = AdminGatewayUpdateResult(
            gateway: gateway,
            runtimeStatus: "running",
            lastError: nil,
            restartPerformed: false,
            configChanged: false,
            userNotice: nil
        )
        XCTAssertEqual(
            gatewayUpdateNoticeText(for: unchanged),
            "Gateway 配置已保存。"
        )
    }

    func testDecodesGatewayDeleteResultPayload() throws {
        let deleteData = """
        {
          "ok": true,
          "id": "gateway_main",
          "runtime_status_before_delete": "running",
          "stop_performed": true,
          "user_notice": "Gateway 已删除。运行中的实例已先停止。"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(AdminGatewayDeleteResult.self, from: deleteData)

        XCTAssertEqual(result.ok, true)
        XCTAssertEqual(result.id, "gateway_main")
        XCTAssertEqual(result.runtimeStatusBeforeDelete, "running")
        XCTAssertEqual(result.stopPerformed, true)
        XCTAssertEqual(result.userNotice, "Gateway 已删除。运行中的实例已先停止。")
    }

    func testGatewayDeleteNoticeTextPrefersServerNoticeAndFallsBackLocally() {
        let withNotice = AdminGatewayDeleteResult(
            ok: true,
            id: "gateway_main",
            runtimeStatusBeforeDelete: "running",
            stopPerformed: true,
            userNotice: "Gateway 已删除。运行中的实例已先停止。"
        )
        XCTAssertEqual(
            gatewayDeleteNoticeText(for: withNotice),
            "Gateway 已删除。运行中的实例已先停止。"
        )

        let stoppedDelete = AdminGatewayDeleteResult(
            ok: true,
            id: "gateway_main",
            runtimeStatusBeforeDelete: "stopped",
            stopPerformed: false,
            userNotice: nil
        )
        XCTAssertEqual(
            gatewayDeleteNoticeText(for: stoppedDelete),
            "Gateway 已删除。"
        )
    }

    func testBuildsReadableAdminApiErrorMessageForReferencedProviderConflict() {
        let errorData = """
        {
          "error": "provider is referenced by gateways",
          "id": "provider_main",
          "referenced_by_gateway_ids": ["gateway_main", "gateway_backup"]
        }
        """.data(using: .utf8)!

        XCTAssertEqual(
            adminAPIErrorMessage(from: errorData, statusCode: 409),
            "provider is referenced by gateways: gateway_main, gateway_backup"
        )
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
                autoStart: true,
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
                autoStart: false,
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

    func testGatewayFormSupportBuildsSnapshotAndFooterSummary() {
        let providers = [
            AdminProvider(
                id: "glm-coding-id",
                name: "glm-coding",
                kind: "anthropic",
                baseURL: "https://open.bigmodel.cn/api/anthropic",
                apiKey: "sk-gateway",
                models: ["GLM-5"],
                enabled: true
            )
        ]

        let snapshot = GatewayFormSupport.snapshot(
            name: "glm-coding",
            listenHost: "127.0.0.1",
            listenPort: "18072",
            inboundProtocol: "anthropic",
            upstreamProtocol: "anthropic",
            defaultProviderID: "glm-coding-id",
            defaultModel: "GLM-5",
            enabled: true,
            autoStart: true,
            protocolConfigJSON: """
            {
              "compatibility_mode": "compatible"
            }
            """,
            providers: providers
        )

        XCTAssertEqual(snapshot.title, "glm-coding")
        XCTAssertEqual(snapshot.endpoint, "127.0.0.1:18072")
        XCTAssertEqual(snapshot.providerLabel, "glm-coding-id")
        XCTAssertEqual(snapshot.protocolSummary, "Anthropic -> Anthropic")
        XCTAssertEqual(snapshot.runtimeStatus, "Active")
        XCTAssertEqual(snapshot.startupMode, "Automatic")
        XCTAssertEqual(snapshot.routingMode, "Mapped")
        XCTAssertEqual(snapshot.footerSummary, "127.0.0.1:18072 · Auto Start On")
    }

    func testGatewayFormSupportPreservesUnknownSelectionsAsFallbackOptions() {
        let providers = [
            AdminProvider(
                id: "provider_main",
                name: "Main Provider",
                kind: "openai",
                baseURL: "https://api.openai.com/v1",
                apiKey: "sk-main",
                models: ["gpt-4o-mini"],
                enabled: true
            )
        ]

        let providerOptions = GatewayFormSupport.providerOptions(
            providers: providers,
            selectedProviderID: "legacy_provider"
        )
        let inboundOptions = GatewayFormSupport.protocolOptions(
            kind: .inbound,
            selectedValue: "legacy-inbound"
        )
        let upstreamOptions = GatewayFormSupport.protocolOptions(
            kind: .upstream,
            selectedValue: "legacy-upstream"
        )

        XCTAssertEqual(providerOptions.first?.id, "legacy_provider")
        XCTAssertEqual(providerOptions.first?.title, "Current value: legacy_provider")
        XCTAssertEqual(providerOptions.first?.subtitle, "Unavailable provider")
        XCTAssertTrue(providerOptions.first?.isFallback == true)

        XCTAssertEqual(inboundOptions.first?.id, "legacy-inbound")
        XCTAssertEqual(inboundOptions.first?.title, "Current value: legacy-inbound")
        XCTAssertTrue(inboundOptions.first?.isFallback == true)

        XCTAssertEqual(upstreamOptions.first?.id, "legacy-upstream")
        XCTAssertEqual(upstreamOptions.first?.title, "Current value: legacy-upstream")
        XCTAssertTrue(upstreamOptions.first?.isFallback == true)
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
            upstreamProtocol: "provider_default",
            protocolConfigJSON: ["compatibility_mode": .string("compatible")],
            defaultProviderId: "provider_ui",
            defaultModel: "gpt-4o-mini",
            enabled: true,
            autoStart: true
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
        XCTAssertEqual(gatewayJSON["upstream_protocol"] as? String, "provider_default")
        XCTAssertEqual(gatewayJSON["default_provider_id"] as? String, "provider_ui")
        XCTAssertEqual(gatewayJSON["default_model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(gatewayJSON["auto_start"] as? Bool, true)
        let createProtocolConfig = gatewayJSON["protocol_config_json"] as? [String: String]
        XCTAssertEqual(createProtocolConfig?["compatibility_mode"], "compatible")

        XCTAssertEqual(updateProviderJSON["base_url"] as? String, "https://api.openai.com/v1")
        XCTAssertEqual(updateProviderJSON["api_key"] as? String, "sk-test-updated")
        XCTAssertEqual((updateProviderJSON["models"] as? [String])?.first, "gpt-4.1-mini")
        XCTAssertEqual(updateProviderJSON["enabled"] as? Bool, false)
    }

    func testEncodesGatewayUpdatePayloadWithSnakeCaseKeys() throws {
        let gatewayInput = UpdateGatewayInput(
            name: "UI Gateway Updated",
            listenHost: "127.0.0.1",
            listenPort: 19090,
            inboundProtocol: "openai",
            upstreamProtocol: "provider_default",
            protocolConfigJSON: ["compatibility_mode": .string("strict")],
            defaultProviderId: "provider_ui",
            defaultModel: "gpt-4.1-mini",
            enabled: false,
            autoStart: true
        )

        let gatewayData = try JSONEncoder().encode(gatewayInput)
        let gatewayJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: gatewayData) as? [String: Any]
        )

        XCTAssertEqual(gatewayJSON["listen_host"] as? String, "127.0.0.1")
        XCTAssertEqual(gatewayJSON["listen_port"] as? Int, 19090)
        XCTAssertEqual(gatewayJSON["upstream_protocol"] as? String, "provider_default")
        XCTAssertEqual(gatewayJSON["default_provider_id"] as? String, "provider_ui")
        XCTAssertEqual(gatewayJSON["auto_start"] as? Bool, true)
        XCTAssertEqual(gatewayJSON["enabled"] as? Bool, false)
        let protocolConfig = gatewayJSON["protocol_config_json"] as? [String: String]
        XCTAssertEqual(protocolConfig?["compatibility_mode"], "strict")
    }

    func testDecodesPaginatedLogsPayload() throws {
        let logsData = """
        {
          "items": [
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
          ],
          "next_cursor": {
            "created_at": "2026-03-03T09:59:00Z",
            "request_id": "req_000"
          },
          "has_more": true
        }
        """.data(using: .utf8)!

        let page = try AdminApiClient.decodeLogPage(from: logsData)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.requestID, "req_001")
        XCTAssertEqual(page.items.first?.statusCode, 200)
        XCTAssertEqual(page.hasMore, true)
        XCTAssertEqual(page.nextCursor?.requestID, "req_000")
    }

    func testDecodesPaginatedLogsPayloadWithFullAdminLogContract() throws {
        let logsData = """
        {
          "items": [
            {
              "request_id": "req_full_001",
              "gateway_id": "gateway_main",
              "provider_id": "provider_main",
              "model": "gpt-5",
              "inbound_protocol": "openai",
              "upstream_protocol": "openai",
              "model_requested": "gpt-5-codex",
              "model_effective": "gpt-5",
              "status_code": 502,
              "latency_ms": 1320,
              "stream": true,
              "first_byte_ms": 420,
              "input_tokens": 800,
              "output_tokens": 120,
              "cached_tokens": 240,
              "total_tokens": 1160,
              "usage_json": "{\\"prompt_tokens\\":800,\\"completion_tokens\\":120}",
              "error_stage": "upstream_response",
              "error_type": "upstream_error",
              "error": "provider timeout",
              "created_at": "2026-03-03T10:00:00Z"
            }
          ],
          "next_cursor": null,
          "has_more": false
        }
        """.data(using: .utf8)!

        let page = try AdminApiClient.decodeLogPage(from: logsData)
        let log = try XCTUnwrap(page.items.first)

        XCTAssertEqual(log.inboundProtocol, "openai")
        XCTAssertEqual(log.upstreamProtocol, "openai")
        XCTAssertEqual(log.modelRequested, "gpt-5-codex")
        XCTAssertEqual(log.modelEffective, "gpt-5")
        XCTAssertEqual(log.stream, true)
        XCTAssertEqual(log.firstByteMs, 420)
        XCTAssertEqual(log.inputTokens, 800)
        XCTAssertEqual(log.outputTokens, 120)
        XCTAssertEqual(log.cachedTokens, 240)
        XCTAssertEqual(log.totalTokens, 1160)
        XCTAssertEqual(log.usageJSON, "{\"prompt_tokens\":800,\"completion_tokens\":120}")
        XCTAssertEqual(log.errorStage, "upstream_response")
        XCTAssertEqual(log.errorType, "upstream_error")
    }

    func testAdminLogModelDisplayTextUsesRequestedAndEffectiveModels() {
        let remapped = AdminLog(
            requestID: "req_model_map",
            gatewayID: "gw",
            providerID: "pv",
            model: "gpt-5",
            inboundProtocol: "openai",
            upstreamProtocol: "openai",
            modelRequested: "gpt-5-codex",
            modelEffective: "gpt-5",
            statusCode: 200,
            latencyMs: 120,
            error: nil,
            createdAt: "2026-03-03T10:00:00Z"
        )
        let stable = AdminLog(
            requestID: "req_model_same",
            gatewayID: "gw",
            providerID: "pv",
            model: "gpt-5",
            inboundProtocol: "openai",
            upstreamProtocol: "openai",
            modelRequested: "gpt-5",
            modelEffective: "gpt-5",
            statusCode: 200,
            latencyMs: 120,
            error: nil,
            createdAt: "2026-03-03T10:01:00Z"
        )

        XCTAssertEqual(remapped.modelDisplayText, "gpt-5-codex -> gpt-5")
        XCTAssertEqual(stable.modelDisplayText, "gpt-5")
    }

    func testAdminLogTokenBreakdownTextIncludesAllTokenDimensions() {
        let log = AdminLog(
            requestID: "req_tokens",
            gatewayID: "gw",
            providerID: "pv",
            model: "gpt-5",
            statusCode: 200,
            latencyMs: 120,
            inputTokens: 800,
            outputTokens: 120,
            cachedTokens: 240,
            totalTokens: 1160,
            error: nil,
            createdAt: "2026-03-03T10:00:00Z"
        )

        XCTAssertEqual(log.tokenBreakdownText, "In 800 · Out 120 · Cached 240 · Total 1160")
    }

    func testLogStreamCardModelPrefersErrorSummaryForFailedLog() {
        let log = AdminLog(
            requestID: "req_failed",
            gatewayID: "gw",
            providerID: "pv",
            model: "gpt-5",
            modelRequested: "gpt-5-codex",
            modelEffective: "gpt-5",
            statusCode: 502,
            latencyMs: 1820,
            errorStage: "upstream_response",
            errorType: "upstream_error",
            error: "provider timeout",
            createdAt: "2026-03-03T10:00:00Z"
        )

        let model = LogStreamCardModel.make(log: log)

        XCTAssertEqual(model.summaryText, "provider timeout")
        XCTAssertEqual(model.modelText, "gpt-5-codex -> gpt-5")
        XCTAssertEqual(model.routeText, "gw -> pv")
        XCTAssertEqual(model.statusText, "502")
    }

    func testLogStreamCardModelKeepsRouteModelLatencyAndTimeForSuccessfulLog() {
        let log = AdminLog(
            requestID: "req_success",
            gatewayID: "gw",
            providerID: "pv",
            model: "gpt-5",
            statusCode: 200,
            latencyMs: 140,
            createdAt: "2026-03-03T10:00:00Z"
        )

        let model = LogStreamCardModel.make(log: log)

        XCTAssertEqual(model.summaryText, "gpt-5")
        XCTAssertEqual(model.routeText, "gw -> pv")
        XCTAssertEqual(model.latencyText, "140 ms")
        XCTAssertEqual(model.createdAtText, "2026-03-03T10:00:00Z")
    }

    func testLogsWorkbenchExpansionStateAllowsOnlySingleExpandedLog() {
        var state = LogsWorkbenchExpansionState()

        state.toggle(requestID: "req_a")
        XCTAssertEqual(state.expandedRequestID, "req_a")

        state.toggle(requestID: "req_b")
        XCTAssertEqual(state.expandedRequestID, "req_b")

        state.toggle(requestID: "req_b")
        XCTAssertNil(state.expandedRequestID)
    }

    func testLogsWorkbenchExpansionStateResetsWhenExpandedLogBecomesInvalid() {
        var state = LogsWorkbenchExpansionState(expandedRequestID: "req_b")
        let logs = [
            AdminLog(
                requestID: "req_a",
                gatewayID: "gw",
                providerID: "pv",
                model: "gpt-5",
                statusCode: 200,
                latencyMs: 100,
                createdAt: "2026-03-03T10:00:00Z"
            )
        ]

        state.reconcileVisibleLogs(logs)
        XCTAssertNil(state.expandedRequestID)

        state.toggle(requestID: "req_a")
        XCTAssertEqual(state.expandedRequestID, "req_a")

        state.resetForFilterChange()
        XCTAssertNil(state.expandedRequestID)
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
            ),
            AdminLog(
                requestID: "req_soft_err",
                gatewayID: "gw_c",
                providerID: "pv_c",
                model: "gpt-4.1-mini",
                statusCode: 200,
                latencyMs: 180,
                error: "degraded to estimate",
                createdAt: "2026-03-03T10:02:00Z"
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
        XCTAssertEqual(errorsOnly.count, 2)
        XCTAssertEqual(errorsOnly.map(\.requestID), ["req_err", "req_soft_err"])
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

    func testAdminStatsOverviewDecodingUsesAdminContract() throws {
        let data = """
        {
          "total_requests": 72,
          "successful_requests": 60,
          "error_requests": 12,
          "success_rate": 83.3,
          "requests_per_minute": 1.2,
          "total_tokens": 123456,
          "cached_tokens": 32000,
          "by_gateway": [
            {
              "gateway_id": "gw_alpha",
              "request_count": 40,
              "success_count": 35,
              "error_count": 5,
              "total_tokens": 64000,
              "cached_tokens": 18000,
              "avg_latency": 420
            }
          ],
          "by_provider": [
            {
              "provider_id": "pv_main",
              "request_count": 72,
              "success_count": 60,
              "error_count": 12,
              "total_tokens": 123456,
              "cached_tokens": 32000,
              "avg_latency": 380
            }
          ],
          "by_model": [
            {
              "model": "gpt-4.1-mini",
              "request_count": 51,
              "success_count": 46,
              "error_count": 5,
              "total_tokens": 92000,
              "cached_tokens": 22000,
              "avg_latency": 410
            }
          ]
        }
        """.data(using: .utf8)!

        let overview = try AdminApiClient.decodeStatsOverview(from: data)

        XCTAssertEqual(overview.totalRequests, 72)
        XCTAssertEqual(overview.successRate, 83.3, accuracy: 0.001)
        XCTAssertEqual(overview.cachedTokens, 32_000)
        XCTAssertEqual(overview.byGateway.first?.gatewayID, "gw_alpha")
        XCTAssertEqual(overview.byGateway.first?.cachedTokens, 18_000)
        XCTAssertEqual(overview.byProvider.first?.providerID, "pv_main")
        XCTAssertEqual(overview.byProvider.first?.cachedTokens, 32_000)
        XCTAssertEqual(overview.byModel.first?.model, "gpt-4.1-mini")
        XCTAssertEqual(overview.byModel.first?.cachedTokens, 22_000)
    }

    func testAdminStatsTrendDecodingUsesAdminContract() throws {
        let data = """
        {
          "period": "1h",
          "interval": "5m",
          "data": [
            {
              "timestamp": "2026-03-11 10:00:00",
              "request_count": 12,
              "avg_latency": 180,
              "error_count": 1,
              "input_tokens": 800,
              "output_tokens": 1200,
              "cached_tokens": 300
            },
            {
              "timestamp": "2026-03-11 10:05:00",
              "request_count": 18,
              "avg_latency": 240,
              "error_count": 3,
              "input_tokens": 1000,
              "output_tokens": 1800,
              "cached_tokens": 500
            }
          ]
        }
        """.data(using: .utf8)!

        let trend = try AdminApiClient.decodeStatsTrend(from: data)

        XCTAssertEqual(trend.period, "1h")
        XCTAssertEqual(trend.interval, "5m")
        XCTAssertEqual(trend.data.count, 2)
        XCTAssertEqual(trend.data.last?.avgLatency, 240)
        XCTAssertEqual(trend.data.first?.cachedTokens, 300)
        XCTAssertEqual(trend.data.last?.cachedTokens, 500)
    }

    func testTrafficMonitorModelBuildsKpisAlertsAndBreakdowns() {
        let overview = AdminStatsOverview(
            totalRequests: 72,
            successfulRequests: 60,
            errorRequests: 12,
            successRate: 83.3,
            requestsPerMinute: 1.2,
            totalTokens: 123_456,
            byGateway: [
                AdminGatewayStats(
                    gatewayID: "gw_alpha",
                    requestCount: 40,
                    successCount: 35,
                    errorCount: 5,
                    totalTokens: 64_000,
                    avgLatency: 420
                ),
                AdminGatewayStats(
                    gatewayID: "gw_beta",
                    requestCount: 32,
                    successCount: 25,
                    errorCount: 7,
                    totalTokens: 59_456,
                    avgLatency: 1_250
                )
            ],
            byProvider: [
                AdminProviderStats(
                    providerID: "pv_main",
                    requestCount: 72,
                    successCount: 60,
                    errorCount: 12,
                    totalTokens: 123_456,
                    avgLatency: 380
                )
            ],
            byModel: [
                AdminModelStats(
                    model: "gpt-4.1-mini",
                    requestCount: 51,
                    successCount: 46,
                    errorCount: 5,
                    totalTokens: 92_000,
                    avgLatency: 410
                )
            ]
        )
        let trend = AdminStatsTrend(
            period: "1h",
            interval: "5m",
            data: [
                AdminStatsTrendPoint(
                    timestamp: "2026-03-11 10:00:00",
                    requestCount: 12,
                    avgLatency: 180,
                    errorCount: 1,
                    inputTokens: 800,
                    outputTokens: 1_200
                ),
                AdminStatsTrendPoint(
                    timestamp: "2026-03-11 10:05:00",
                    requestCount: 18,
                    avgLatency: 240,
                    errorCount: 3,
                    inputTokens: 1_000,
                    outputTokens: 1_800
                )
            ]
        )

        let model = TrafficAnalyticsModel.make(
            overview: overview,
            trend: trend,
            selectedPeriod: "1h"
        )

        XCTAssertEqual(model.requestsPerMinuteText, "1.2")
        XCTAssertEqual(model.successRateText, "83.3%")
        XCTAssertEqual(model.topGatewayID, "gw_alpha")
        XCTAssertEqual(model.topProviderID, "pv_main")
        XCTAssertEqual(model.topModelName, "gpt-4.1-mini")
        XCTAssertEqual(model.gatewayBreakdown.first?.title, "gw_alpha")
        XCTAssertEqual(model.alerts.first?.level, .error)
    }

    func testTrafficMonitorModelExposesCompactTopRowsForDenseLayout() {
        let rows = [
            TrafficBreakdownRow(title: "a", requestCountText: "1", latencyText: "1", errorText: "0", tokenText: "1"),
            TrafficBreakdownRow(title: "b", requestCountText: "2", latencyText: "2", errorText: "0", tokenText: "2"),
            TrafficBreakdownRow(title: "c", requestCountText: "3", latencyText: "3", errorText: "0", tokenText: "3"),
            TrafficBreakdownRow(title: "d", requestCountText: "4", latencyText: "4", errorText: "0", tokenText: "4")
        ]
        let model = TrafficAnalyticsModel(
            totalRequests: 0,
            errorCount: 0,
            successCount: 0,
            averageLatencyText: "0 ms",
            requestsPerMinuteText: "0.0",
            successRateText: "0.0%",
            totalTokensText: "0",
            topGatewayID: "No gateway",
            topProviderID: "No provider",
            topModelName: "No model",
            gatewayBreakdown: rows,
            providerBreakdown: rows,
            modelBreakdown: rows,
            trendPoints: [],
            alerts: [],
            selectedPeriod: "1h",
            hasData: false,
            gatewayStatsForKpi: [],
            totalInputTokens: 0,
            totalOutputTokens: 0,
            totalCachedTokens: 0
        )

        XCTAssertEqual(model.compactGatewayBreakdown.count, 3)
        XCTAssertEqual(model.compactGatewayBreakdown.map(\.title), ["a", "b", "c"])
        XCTAssertEqual(model.compactProviderBreakdown.count, 3)
        XCTAssertEqual(model.compactModelBreakdown.count, 3)
    }

    func testTrafficMonitorModelExposesKpiStripItems() {
        let overview = AdminStatsOverview(
            totalRequests: 95,
            successfulRequests: 72,
            errorRequests: 23,
            successRate: 75.8,
            requestsPerMinute: 0.1,
            totalTokens: 146_184,
            byGateway: [],
            byProvider: [],
            byModel: []
        )

        let model = TrafficAnalyticsModel.make(
            overview: overview,
            trend: AdminStatsTrend(period: "24h", interval: "1h", data: []),
            selectedPeriod: "24h"
        )

        XCTAssertEqual(model.kpiStripItems.count, 4)
        XCTAssertEqual(
            model.kpiStripItems.map(\.title),
            ["Requests / min", "Success Rate", "Avg Latency", "Total Tokens"]
        )
        XCTAssertEqual(model.kpiStripItems.first?.value, "0.1")
    }

    func testTrafficMonitorModelExposesKpiSupplementRows() {
        let overview = AdminStatsOverview(
            totalRequests: 120,
            successfulRequests: 100,
            errorRequests: 20,
            successRate: 83.3,
            requestsPerMinute: 2.0,
            totalTokens: 9_500,
            cachedTokens: 900,
            byGateway: [
                AdminGatewayStats(
                    gatewayID: "gw_alpha",
                    requestCount: 72,
                    successCount: 65,
                    errorCount: 7,
                    totalTokens: 4_800,
                    cachedTokens: 500,
                    avgLatency: 420
                ),
                AdminGatewayStats(
                    gatewayID: "gw_beta",
                    requestCount: 36,
                    successCount: 29,
                    errorCount: 7,
                    totalTokens: 3_400,
                    cachedTokens: 300,
                    avgLatency: 780
                ),
                AdminGatewayStats(
                    gatewayID: "gw_gamma",
                    requestCount: 12,
                    successCount: 6,
                    errorCount: 6,
                    totalTokens: 1_300,
                    cachedTokens: 100,
                    avgLatency: 1_600
                )
            ],
            byProvider: [],
            byModel: []
        )
        let trend = AdminStatsTrend(
            period: "1h",
            interval: "5m",
            data: [
                AdminStatsTrendPoint(
                    timestamp: "2026-03-11 10:00:00",
                    requestCount: 40,
                    avgLatency: 300,
                    errorCount: 4,
                    inputTokens: 1_000,
                    outputTokens: 1_500,
                    cachedTokens: 400
                ),
                AdminStatsTrendPoint(
                    timestamp: "2026-03-11 10:05:00",
                    requestCount: 50,
                    avgLatency: 450,
                    errorCount: 7,
                    inputTokens: 1_200,
                    outputTokens: 1_800,
                    cachedTokens: 500
                )
            ]
        )

        let model = TrafficAnalyticsModel.make(
            overview: overview,
            trend: trend,
            selectedPeriod: "1h"
        )

        XCTAssertEqual(
            model.kpiStripItems.map(\.title),
            ["Requests / min", "Success Rate", "Avg Latency", "Total Tokens"]
        )
        XCTAssertEqual(
            model.kpiStripItems[0].detailRows,
            [
                TrafficKpiSupplementRow(label: "gw_alpha", value: "1.2 rpm"),
                TrafficKpiSupplementRow(label: "gw_beta", value: "0.6 rpm")
            ]
        )
        XCTAssertEqual(
            model.kpiStripItems[1].detailRows,
            [
                TrafficKpiSupplementRow(label: "gw_alpha", value: "65 ok / 7 err"),
                TrafficKpiSupplementRow(label: "gw_beta", value: "29 ok / 7 err")
            ]
        )
        XCTAssertEqual(
            model.kpiStripItems[2].detailRows,
            [
                TrafficKpiSupplementRow(label: "gw_alpha", value: "420 ms"),
                TrafficKpiSupplementRow(label: "gw_beta", value: "780 ms")
            ]
        )
        XCTAssertEqual(
            model.kpiStripItems[3].detailRows,
            [
                TrafficKpiSupplementRow(label: "Input", value: "2,200"),
                TrafficKpiSupplementRow(label: "Output", value: "3,300"),
                TrafficKpiSupplementRow(label: "Cached", value: "900")
            ]
        )
    }

    func testAdminStatsOverviewAndTrendDecodeCachedTokens() throws {
        let overviewData = """
        {
          "total_requests": 72,
          "successful_requests": 60,
          "error_requests": 12,
          "success_rate": 83.3,
          "requests_per_minute": 1.2,
          "total_tokens": 123456,
          "cached_tokens": 32000,
          "by_gateway": [
            {
              "gateway_id": "gw_alpha",
              "request_count": 40,
              "success_count": 35,
              "error_count": 5,
              "total_tokens": 64000,
              "cached_tokens": 18000,
              "avg_latency": 420
            }
          ],
          "by_provider": [
            {
              "provider_id": "pv_main",
              "request_count": 72,
              "success_count": 60,
              "error_count": 12,
              "total_tokens": 123456,
              "cached_tokens": 32000,
              "avg_latency": 380
            }
          ],
          "by_model": [
            {
              "model": "gpt-4.1-mini",
              "request_count": 51,
              "success_count": 46,
              "error_count": 5,
              "total_tokens": 92000,
              "cached_tokens": 22000,
              "avg_latency": 410
            }
          ]
        }
        """.data(using: .utf8)!

        let trendData = """
        {
          "period": "1h",
          "interval": "5m",
          "data": [
            {
              "timestamp": "2026-03-11 10:00:00",
              "request_count": 12,
              "avg_latency": 180,
              "error_count": 1,
              "input_tokens": 800,
              "output_tokens": 1200,
              "cached_tokens": 300
            }
          ]
        }
        """.data(using: .utf8)!

        let overview = try AdminApiClient.decodeStatsOverview(from: overviewData)
        let trend = try AdminApiClient.decodeStatsTrend(from: trendData)

        XCTAssertEqual(overview.cachedTokens, 32_000)
        XCTAssertEqual(overview.byGateway.first?.cachedTokens, 18_000)
        XCTAssertEqual(trend.data.first?.cachedTokens, 300)
    }

    func testTrafficMonitorModelKeepsRenderableScaffoldWhenStatsAreEmpty() {
        let overview = AdminStatsOverview(
            totalRequests: 0,
            successfulRequests: 0,
            errorRequests: 0,
            successRate: 0,
            requestsPerMinute: 0,
            totalTokens: 0,
            byGateway: [],
            byProvider: [],
            byModel: []
        )
        let trend = AdminStatsTrend(period: "1h", interval: "5m", data: [])

        let model = TrafficAnalyticsModel.make(
            overview: overview,
            trend: trend,
            selectedPeriod: "1h"
        )

        XCTAssertEqual(model.requestsPerMinuteText, "0.0")
        XCTAssertEqual(model.successRateText, "0.0%")
        XCTAssertEqual(model.totalTokensText, "0")
        XCTAssertEqual(model.alerts.first?.level, .info)
        XCTAssertFalse(model.hasData)
    }

    func testProviderKindOptionsExposeStableMachineValuesAndLabels() {
        XCTAssertEqual(
            ProviderKindOption.allCases.map(\.rawValue),
            [
                "openai",
                "openai-response",
                "gemini",
                "anthropic",
                "azure-openai",
                "new-api",
                "ollama"
            ]
        )
        XCTAssertEqual(ProviderKindOption.openAIResponse.label, "OpenAI-Response")
        XCTAssertEqual(ProviderKindOption.azureOpenAI.label, "Azure OpenAI")
        XCTAssertEqual(ProviderKindOption.newAPI.label, "New API")
    }

    func testGatewayProtocolOptionsStayAlignedWithProviderKinds() {
        let inboundOptions = GatewayFormSupport.protocolOptions(
            kind: .inbound,
            selectedValue: "openai"
        )
        let upstreamOptions = GatewayFormSupport.protocolOptions(
            kind: .upstream,
            selectedValue: "provider_default"
        )

        XCTAssertEqual(
            inboundOptions.map(\.id),
            ProviderKindOption.allCases.map(\.rawValue)
        )
        XCTAssertEqual(
            upstreamOptions.map(\.id),
            ["provider_default"] + ProviderKindOption.allCases.map(\.rawValue)
        )
        XCTAssertEqual(
            GatewayFormSupport.protocolTitle(for: "openai-response", kind: .inbound),
            "OpenAI-Response"
        )
        XCTAssertEqual(
            GatewayFormSupport.protocolTitle(for: "provider_default", kind: .upstream),
            "Provider Default"
        )
    }
}
