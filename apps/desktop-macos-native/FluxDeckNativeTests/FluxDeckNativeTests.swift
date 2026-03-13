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

    func testShellToolbarModelBuildsEndpointAndRefreshMetadata() {
        let status = ShellStatusSummary.make(
            isLoading: false,
            loadError: nil,
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
            ]
        )

        let model = ShellToolbarModel.make(
            title: "Traffic",
            adminBaseURL: "http://127.0.0.1:7777",
            lastRefreshText: "19:14:53",
            isRefreshing: true,
            statusSummary: status
        )

        XCTAssertEqual(model.endpointLabel, "Admin")
        XCTAssertEqual(model.endpointValue, "http://127.0.0.1:7777")
        XCTAssertEqual(model.lastRefreshLabel, "Last refresh 19:14:53")
        XCTAssertTrue(model.isRefreshing)
        XCTAssertEqual(model.statusSummary.gatewayLabel, "1 running")
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

    func testTopologyGraphCoalescesDuplicateEntrypoints() {
        let gateways = [
            AdminGateway(
                id: "gw_a",
                name: "Gateway A",
                listenHost: "127.0.0.1",
                listenPort: 18081,
                inboundProtocol: "openai",
                defaultProviderId: "pv_a",
                enabled: true,
                autoStart: true,
                runtimeStatus: "running",
                lastError: nil
            ),
            AdminGateway(
                id: "gw_b",
                name: "Gateway B",
                listenHost: "127.0.0.1",
                listenPort: 18081,
                inboundProtocol: "openai",
                defaultProviderId: "pv_b",
                enabled: true,
                autoStart: true,
                runtimeStatus: "running",
                lastError: nil
            )
        ]

        let graph = TopologyGraph.make(
            gateways: gateways,
            providers: [],
            logs: [
                AdminLog(
                    requestID: "req_1",
                    gatewayID: "gw_a",
                    providerID: "pv_a",
                    model: "gpt-4o-mini",
                    statusCode: 200,
                    latencyMs: 100,
                    totalTokens: 120,
                    createdAt: "2026-03-06T10:00:00Z"
                ),
                AdminLog(
                    requestID: "req_2",
                    gatewayID: "gw_b",
                    providerID: "pv_b",
                    model: "gpt-4o-mini",
                    statusCode: 200,
                    latencyMs: 120,
                    totalTokens: 80,
                    createdAt: "2026-03-06T10:01:00Z"
                )
            ]
        )

        XCTAssertEqual(graph.columns[0].nodes.count, 1)
        XCTAssertEqual(graph.columns[0].nodes.first?.id, "entrypoint:127.0.0.1:18081")
        XCTAssertEqual(graph.columns[0].nodes.first?.totalTokens, 200)
        XCTAssertEqual(graph.columns[0].nodes.first?.requestCount, 2)
    }

    func testTopologyGraphAggregatesTokenSegmentsPerEdge() throws {
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
                    models: ["gpt-4o-mini", "gpt-4.1-mini"],
                    enabled: true
                )
            ],
            logs: [
                AdminLog(
                    requestID: "req_1",
                    gatewayID: "gw",
                    providerID: "pv",
                    model: "fallback-model",
                    modelEffective: "gpt-4o-mini",
                    statusCode: 200,
                    latencyMs: 120,
                    inputTokens: 100,
                    outputTokens: 50,
                    cachedTokens: 10,
                    totalTokens: 150,
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
                    inputTokens: 40,
                    outputTokens: 20,
                    cachedTokens: 5,
                    totalTokens: 60,
                    error: "bad gateway",
                    createdAt: "2026-03-06T10:01:00Z"
                ),
                AdminLog(
                    requestID: "req_3",
                    gatewayID: "gw",
                    providerID: "pv",
                    model: "gpt-4.1-mini",
                    statusCode: 200,
                    latencyMs: 90,
                    inputTokens: 60,
                    outputTokens: 20,
                    cachedTokens: 0,
                    totalTokens: 80,
                    error: nil,
                    createdAt: "2026-03-06T10:02:00Z"
                )
            ]
        )

        let gatewayNode = try XCTUnwrap(graph.columns[1].nodes.first(where: { $0.id == "gw" }))
        XCTAssertEqual(gatewayNode.totalTokens, 290)
        XCTAssertEqual(gatewayNode.requestCount, 3)
        XCTAssertEqual(gatewayNode.cachedTokens, 15)
        XCTAssertEqual(gatewayNode.errorCount, 1)

        let providerNode = try XCTUnwrap(graph.columns[2].nodes.first(where: { $0.id == "pv" }))
        XCTAssertEqual(providerNode.totalTokens, 290)
        XCTAssertEqual(providerNode.requestCount, 3)
        XCTAssertEqual(providerNode.cachedTokens, 15)
        XCTAssertEqual(providerNode.errorCount, 1)

        let providerEdge = try XCTUnwrap(graph.edges.first(where: { $0.id == "gw->pv" }))
        XCTAssertEqual(providerEdge.totalTokens, 290)
        XCTAssertEqual(providerEdge.requestCount, 3)
        XCTAssertEqual(providerEdge.cachedTokens, 15)
        XCTAssertEqual(providerEdge.errorCount, 1)
        XCTAssertEqual(providerEdge.segments.map(\.modelName), ["gpt-4o-mini", "gpt-4.1-mini"])
        XCTAssertEqual(providerEdge.segments.map(\.totalTokens), [210, 80])
        XCTAssertEqual(providerEdge.segments.map(\.requestCount), [2, 1])
    }

    func testTopologyGraphFallsBackForMissingTokenFields() throws {
        let graph = TopologyGraph.make(
            gateways: [
                AdminGateway(
                    id: "gw",
                    name: "Gateway",
                    listenHost: "0.0.0.0",
                    listenPort: 18072,
                    inboundProtocol: "openai",
                    defaultProviderId: "pv_missing",
                    enabled: true,
                    autoStart: true,
                    runtimeStatus: "running",
                    lastError: nil
                )
            ],
            providers: [],
            logs: [
                AdminLog(
                    requestID: "req_1",
                    gatewayID: "gw",
                    providerID: "pv_missing",
                    model: nil,
                    statusCode: 200,
                    latencyMs: 80,
                    inputTokens: 70,
                    outputTokens: 30,
                    cachedTokens: 7,
                    totalTokens: nil,
                    error: nil,
                    createdAt: "2026-03-06T10:00:00Z"
                ),
                AdminLog(
                    requestID: "req_2",
                    gatewayID: "gw",
                    providerID: "pv_missing",
                    model: nil,
                    statusCode: 503,
                    latencyMs: 500,
                    inputTokens: nil,
                    outputTokens: nil,
                    cachedTokens: nil,
                    totalTokens: nil,
                    error: "upstream unavailable",
                    createdAt: "2026-03-06T10:01:00Z"
                )
            ]
        )

        let providerNode = try XCTUnwrap(graph.columns[2].nodes.first(where: { $0.id == "pv_missing" }))
        XCTAssertEqual(providerNode.title, "pv_missing")
        XCTAssertEqual(providerNode.subtitle, "UNKNOWN PROVIDER")
        XCTAssertEqual(providerNode.totalTokens, 100)
        XCTAssertEqual(providerNode.requestCount, 2)
        XCTAssertEqual(providerNode.cachedTokens, 7)
        XCTAssertEqual(providerNode.errorCount, 1)

        let providerEdge = try XCTUnwrap(graph.edges.first(where: { $0.id == "gw->pv_missing" }))
        XCTAssertEqual(providerEdge.totalTokens, 100)
        XCTAssertEqual(providerEdge.requestCount, 2)
        XCTAssertEqual(providerEdge.cachedTokens, 7)
        XCTAssertEqual(providerEdge.errorCount, 1)
        XCTAssertEqual(providerEdge.segments.map(\.modelName), ["unknown"])
        XCTAssertEqual(providerEdge.segments.map(\.totalTokens), [100])
        XCTAssertEqual(providerEdge.segments.map(\.requestCount), [2])
    }

    func testTopologyGraphBuildsTopModelHighlightsAndOtherBucket() throws {
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
                    models: ["m1", "m2", "m3", "m4", "m5", "m6"],
                    enabled: true
                )
            ],
            logs: [
                AdminLog(requestID: "req_1", gatewayID: "gw", providerID: "pv", model: "m1", statusCode: 200, latencyMs: 20, inputTokens: 400, outputTokens: 100, cachedTokens: 10, totalTokens: 500, error: nil, createdAt: "2026-03-06T10:00:00Z"),
                AdminLog(requestID: "req_2", gatewayID: "gw", providerID: "pv", model: "m2", statusCode: 200, latencyMs: 20, inputTokens: 320, outputTokens: 80, cachedTokens: 8, totalTokens: 400, error: nil, createdAt: "2026-03-06T10:01:00Z"),
                AdminLog(requestID: "req_3", gatewayID: "gw", providerID: "pv", model: "m3", statusCode: 200, latencyMs: 20, inputTokens: 240, outputTokens: 60, cachedTokens: 6, totalTokens: 300, error: nil, createdAt: "2026-03-06T10:02:00Z"),
                AdminLog(requestID: "req_4", gatewayID: "gw", providerID: "pv", model: "m4", statusCode: 200, latencyMs: 20, inputTokens: 160, outputTokens: 40, cachedTokens: 4, totalTokens: 200, error: nil, createdAt: "2026-03-06T10:03:00Z"),
                AdminLog(requestID: "req_5", gatewayID: "gw", providerID: "pv", model: "m5", statusCode: 200, latencyMs: 20, inputTokens: 96, outputTokens: 24, cachedTokens: 2, totalTokens: 120, error: nil, createdAt: "2026-03-06T10:04:00Z"),
                AdminLog(requestID: "req_6", gatewayID: "gw", providerID: "pv", model: "m6", statusCode: 503, latencyMs: 20, inputTokens: 48, outputTokens: 12, cachedTokens: 1, totalTokens: 60, error: "upstream unavailable", createdAt: "2026-03-06T10:05:00Z")
            ]
        )

        let defaultHighlighted = graph.applyingHighlightMode(.top5)
        let topThree = graph.applyingHighlightMode(.top3)
        let allModels = graph.applyingHighlightMode(.all)

        let defaultProviderEdge = try XCTUnwrap(defaultHighlighted.edges.first(where: { $0.id == "gw->pv" }))
        XCTAssertEqual(defaultProviderEdge.totalTokens, 1_580)
        XCTAssertEqual(defaultProviderEdge.segments.map(\.modelName), ["m1", "m2", "m3", "m4", "m5", "Other"])
        XCTAssertEqual(defaultProviderEdge.segments.map(\.totalTokens), [500, 400, 300, 200, 120, 60])
        XCTAssertEqual(defaultProviderEdge.segments.last?.requestCount, 1)
        XCTAssertEqual(defaultProviderEdge.segments.last?.cachedTokens, 1)
        XCTAssertEqual(defaultProviderEdge.segments.last?.errorCount, 1)
        XCTAssertEqual(defaultProviderEdge.segments.map(\.totalTokens).reduce(0, +), defaultProviderEdge.totalTokens)

        let topThreeProviderEdge = try XCTUnwrap(topThree.edges.first(where: { $0.id == "gw->pv" }))
        XCTAssertEqual(topThreeProviderEdge.segments.map(\.modelName), ["m1", "m2", "m3", "Other"])
        XCTAssertEqual(topThreeProviderEdge.segments.map(\.totalTokens), [500, 400, 300, 380])
        XCTAssertEqual(topThreeProviderEdge.segments.last?.requestCount, 3)
        XCTAssertEqual(topThreeProviderEdge.segments.last?.cachedTokens, 7)
        XCTAssertEqual(topThreeProviderEdge.segments.last?.errorCount, 1)
        XCTAssertEqual(topThreeProviderEdge.segments.map(\.totalTokens).reduce(0, +), topThreeProviderEdge.totalTokens)

        let allModelsProviderEdge = try XCTUnwrap(allModels.edges.first(where: { $0.id == "gw->pv" }))
        XCTAssertEqual(allModelsProviderEdge.segments.map(\.modelName), ["m1", "m2", "m3", "m4", "m5", "m6"])
        XCTAssertEqual(allModelsProviderEdge.segments.count, 6)
        XCTAssertEqual(allModelsProviderEdge.segments.map(\.totalTokens).reduce(0, +), allModelsProviderEdge.totalTokens)
    }

    func testTopologyCanvasSummaryUsesTokenSemantics() throws {
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
                    kind: "openai-response",
                    baseURL: "https://api.openai.com/v1",
                    apiKey: "sk",
                    models: ["m1", "m2", "m3", "m4"],
                    enabled: true
                )
            ],
            logs: [
                AdminLog(requestID: "req_1", gatewayID: "gw", providerID: "pv", model: "m1", statusCode: 200, latencyMs: 20, inputTokens: 400, outputTokens: 100, cachedTokens: 10, totalTokens: 500, error: nil, createdAt: "2026-03-06T10:00:00Z"),
                AdminLog(requestID: "req_2", gatewayID: "gw", providerID: "pv", model: "m2", statusCode: 200, latencyMs: 20, inputTokens: 240, outputTokens: 60, cachedTokens: 6, totalTokens: 300, error: nil, createdAt: "2026-03-06T10:01:00Z"),
                AdminLog(requestID: "req_3", gatewayID: "gw", providerID: "pv", model: "m3", statusCode: 503, latencyMs: 20, inputTokens: 120, outputTokens: 30, cachedTokens: 2, totalTokens: 150, error: "upstream unavailable", createdAt: "2026-03-06T10:02:00Z"),
                AdminLog(requestID: "req_4", gatewayID: "gw", providerID: "pv", model: "m4", statusCode: 200, latencyMs: 20, inputTokens: 64, outputTokens: 16, cachedTokens: 1, totalTokens: 80, error: nil, createdAt: "2026-03-06T10:03:00Z")
            ]
        )

        let byModel = TopologyCanvasScreenModel.make(
            graph: graph,
            metricMode: .tokens,
            flowMode: .byModel,
            highlightMode: .top3
        )
        let totalOnly = TopologyCanvasScreenModel.make(
            graph: graph,
            metricMode: .tokens,
            flowMode: .totalOnly,
            highlightMode: .top3
        )

        XCTAssertEqual(byModel.summaryTitle, "Hot Paths")
        XCTAssertEqual(byModel.mixTitle, "Model Mix")
        XCTAssertNil(byModel.emptyStateText)
        XCTAssertEqual(byModel.hotPaths.first?.tokenText, "1,030 tok")
        XCTAssertEqual(byModel.hotPaths.first?.requestText, "4 req")
        XCTAssertEqual(byModel.hotPaths.first?.topModelText, "Top model m1")
        XCTAssertEqual(byModel.modelMix.map(\.title), ["m1", "m2", "m3", "Other"])
        XCTAssertEqual(byModel.modelMix.map(\.valueText), ["500 tok", "300 tok", "150 tok", "80 tok"])

        let gatewayNode = try XCTUnwrap(graph.columns[1].nodes.first(where: { $0.id == "gw" }))
        let gatewayCard = TopologyNodeCardModel.make(node: gatewayNode)
        XCTAssertEqual(gatewayCard.primaryMetricText, "1,030 tok")
        XCTAssertEqual(gatewayCard.secondaryMetricText, "4 req")

        let byModelEdge = try XCTUnwrap(byModel.canvasEdges.first(where: { $0.id == "gw->pv" }))
        XCTAssertEqual(byModelEdge.segments.map(\.title), ["m1", "m2", "m3", "Other"])
        XCTAssertEqual(byModelEdge.segments.map(\.emphasisValue), [500, 300, 150, 80])

        let totalOnlyEdge = try XCTUnwrap(totalOnly.canvasEdges.first(where: { $0.id == "gw->pv" }))
        XCTAssertEqual(totalOnlyEdge.segments.map(\.title), ["Total"])
        XCTAssertEqual(totalOnlyEdge.segments.map(\.emphasisValue), [1_030])
    }

    func testTopologyCanvasScreenModelExposesEmptyState() {
        let emptyGraph = TopologyGraph(
            columns: [
                TopologyColumn(title: "Entrypoints", nodes: []),
                TopologyColumn(title: "Gateways", nodes: []),
                TopologyColumn(title: "Providers", nodes: [])
            ],
            edges: []
        )

        let screen = TopologyCanvasScreenModel.make(
            graph: emptyGraph,
            metricMode: .tokens,
            flowMode: .byModel,
            highlightMode: .top5
        )

        XCTAssertEqual(screen.emptyStateText, "No active token routes yet.")
        XCTAssertTrue(screen.hotPaths.isEmpty)
        XCTAssertTrue(screen.modelMix.isEmpty)
        XCTAssertTrue(screen.canvasEdges.isEmpty)
    }

    func testTopologyFlowUsesStableModelPalette() throws {
        let modelA = DesignTokens.topologyModelColor(for: "gpt-4o-mini")
        let modelARepeat = DesignTokens.topologyModelColor(for: "gpt-4o-mini")
        let other = DesignTokens.topologyModelColor(for: "Other")
        let unknown = DesignTokens.topologyModelColor(for: "unknown")
        let warningModel = DesignTokens.topologyModelColor(for: "gemini-2.5-pro")

        XCTAssertEqual(modelA.accessibilityName, modelARepeat.accessibilityName)
        XCTAssertEqual(modelA.fill.description, modelARepeat.fill.description)
        XCTAssertEqual(other.accessibilityName, DesignTokens.statusColors.inactive.accessibilityName)
        XCTAssertEqual(unknown.accessibilityName, DesignTokens.statusColors.inactive.accessibilityName)
        XCTAssertNotEqual(warningModel.accessibilityName, DesignTokens.statusColors.error.accessibilityName)

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
                    models: ["gpt-4o-mini", "gemini-2.5-pro", "unknown"],
                    enabled: true
                )
            ],
            logs: [
                AdminLog(requestID: "req_1", gatewayID: "gw", providerID: "pv", model: "gpt-4o-mini", statusCode: 200, latencyMs: 20, inputTokens: 400, outputTokens: 100, cachedTokens: 10, totalTokens: 500, error: nil, createdAt: "2026-03-06T10:00:00Z"),
                AdminLog(requestID: "req_2", gatewayID: "gw", providerID: "pv", model: "gemini-2.5-pro", statusCode: 503, latencyMs: 20, inputTokens: 120, outputTokens: 30, cachedTokens: 2, totalTokens: 150, error: "upstream unavailable", createdAt: "2026-03-06T10:01:00Z"),
                AdminLog(requestID: "req_3", gatewayID: "gw", providerID: "pv", model: nil, statusCode: 200, latencyMs: 20, inputTokens: 64, outputTokens: 16, cachedTokens: 1, totalTokens: 80, error: nil, createdAt: "2026-03-06T10:02:00Z")
            ]
        )

        let screen = TopologyCanvasScreenModel.make(
            graph: graph,
            metricMode: .tokens,
            flowMode: .byModel,
            highlightMode: .all
        )
        let edge = try XCTUnwrap(screen.canvasEdges.first(where: { $0.id == "gw->pv" }))

        XCTAssertEqual(edge.segments.map(\.semanticColor.accessibilityName), ["running", "cyan", "inactive"])
    }

    func testTopologyFlowAssignsDistinctColorsToRankedModelsWithoutHardcodedNames() throws {
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
                    models: ["m4", "m5", "m6"],
                    enabled: true
                )
            ],
            logs: [
                AdminLog(requestID: "req_1", gatewayID: "gw", providerID: "pv", model: "m4", statusCode: 200, latencyMs: 20, inputTokens: 320, outputTokens: 80, cachedTokens: 4, totalTokens: 400, error: nil, createdAt: "2026-03-06T10:00:00Z"),
                AdminLog(requestID: "req_2", gatewayID: "gw", providerID: "pv", model: "m5", statusCode: 200, latencyMs: 20, inputTokens: 240, outputTokens: 60, cachedTokens: 3, totalTokens: 300, error: nil, createdAt: "2026-03-06T10:01:00Z"),
                AdminLog(requestID: "req_3", gatewayID: "gw", providerID: "pv", model: "m6", statusCode: 200, latencyMs: 20, inputTokens: 160, outputTokens: 40, cachedTokens: 2, totalTokens: 200, error: nil, createdAt: "2026-03-06T10:02:00Z")
            ]
        )

        let screen = TopologyCanvasScreenModel.make(
            graph: graph,
            metricMode: .tokens,
            flowMode: .byModel,
            highlightMode: .all
        )
        let edge = try XCTUnwrap(screen.canvasEdges.first(where: { $0.id == "gw->pv" }))

        XCTAssertEqual(edge.segments.map(\.title), ["m4", "m5", "m6"])
        XCTAssertEqual(edge.segments.map(\.semanticColor.accessibilityName), ["running", "cyan", "warning"])
    }

    func testTopologyCanvasBuildsLightweightNodeSummaries() throws {
        let graph = makeSankeyFixtureGraph()

        let screen = TopologyCanvasScreenModel.make(
            graph: graph,
            metricMode: .tokens,
            flowMode: .byModel,
            highlightMode: .top5
        )

        let gatewaySummary = try XCTUnwrap(screen.nodeSummaries["gw_core"])
        XCTAssertEqual(gatewaySummary.metricLine, "730 tok · 4 req")
        XCTAssertEqual(gatewaySummary.detailLine, "12 cached · 1 err")
        XCTAssertEqual(gatewaySummary.hoverSummary.topModelName, "gpt-4o-mini")
        XCTAssertEqual(gatewaySummary.hoverSummary.errorCount, 1)

        let edgeHover = try XCTUnwrap(
            screen.hoverPayload(
                for: .segment(edgeID: "gw_core->pv_openai", segmentID: "gw_core->pv_openai#gpt-4o-mini")
            )
        )
        XCTAssertEqual(edgeHover.title, "Core Gateway -> OpenAI")
        XCTAssertEqual(edgeHover.rows, ["Model gpt-4o-mini", "640 tok", "3 req", "10 cached", "0 err"])

        XCTAssertEqual(screen.hotPaths.first?.routeText, "Core Gateway -> OpenAI")
        XCTAssertEqual(screen.modelMix.map(\.title), ["gpt-4o-mini", "gemini-2.5-pro", "claude-3-7-sonnet"])
    }

    func testTopologyCanvasAppliesMinimumReadableBandWidth() {
        let tokenSmallWidth = TopologyBandScale.readableWidth(
            value: 8,
            maxValue: 640,
            maxRenderedWidth: 34,
            minReadableWidth: 10
        )
        let tokenLargeWidth = TopologyBandScale.readableWidth(
            value: 640,
            maxValue: 640,
            maxRenderedWidth: 34,
            minReadableWidth: 10
        )

        let requestSmallWidth = TopologyBandScale.readableWidth(
            value: 1,
            maxValue: 3,
            maxRenderedWidth: 34,
            minReadableWidth: 10
        )
        let requestLargeWidth = TopologyBandScale.readableWidth(
            value: 3,
            maxValue: 3,
            maxRenderedWidth: 34,
            minReadableWidth: 10
        )

        XCTAssertEqual(tokenSmallWidth, 10, accuracy: 0.001)
        XCTAssertGreaterThan(tokenLargeWidth, tokenSmallWidth)
        XCTAssertEqual(requestSmallWidth, 10, accuracy: 0.001)
        XCTAssertGreaterThan(requestLargeWidth, requestSmallWidth)
    }

    func testTopologyCanvasPrioritizesBandStageOverHeavyCards() throws {
        let graph = makeSankeyFixtureGraph()
        let screen = TopologyCanvasScreenModel.make(
            graph: graph,
            metricMode: .tokens,
            flowMode: .byModel,
            highlightMode: .top5
        )
        let stage = TopologyCanvasStageLayout.sankey

        XCTAssertEqual(stage.minReadableBandWidth, 10)
        XCTAssertEqual(stage.maxRenderedBandWidth, 34)
        XCTAssertEqual(stage.columnSpacing, 28)
        XCTAssertEqual(stage.rowPitch, 96)
        XCTAssertGreaterThan(stage.gatewayNodeWidth, stage.nodeWidth)

        let providerSummary = try XCTUnwrap(screen.nodeSummaries["pv_openai"])
        XCTAssertEqual(providerSummary.metricLine, "730 tok · 4 req")
        XCTAssertEqual(providerSummary.detailLine, "12 cached · 1 err")
        XCTAssertFalse(providerSummary.metricLine.contains("cached"))
        XCTAssertFalse(providerSummary.metricLine.contains("err"))
    }

    func testTopologyCanvasBuildsHoverTooltipPayloads() throws {
        let graph = makeSankeyFixtureGraph()
        let screen = TopologyCanvasScreenModel.make(
            graph: graph,
            metricMode: .tokens,
            flowMode: .byModel,
            highlightMode: .top5
        )

        let edgeHoverState = screen.hoverState(
            for: .segment(edgeID: "gw_core->pv_openai", segmentID: "gw_core->pv_openai#gpt-4o-mini")
        )
        XCTAssertEqual(edgeHoverState.tooltip?.rows, ["Model gpt-4o-mini", "640 tok", "3 req", "10 cached", "0 err"])
        XCTAssertEqual(edgeHoverState.edgeOpacity(edgeID: "gw_core->pv_openai", segmentID: "gw_core->pv_openai#gpt-4o-mini"), 1)
        XCTAssertEqual(edgeHoverState.edgeOpacity(edgeID: "gw_aux->pv_anthropic", segmentID: "gw_aux->pv_anthropic#gemini-2.5-pro"), 0.16)

        let nodeHoverState = screen.hoverState(for: .node(nodeID: "gw_core"))
        XCTAssertEqual(nodeHoverState.tooltip?.title, "Core Gateway")
        XCTAssertEqual(nodeHoverState.tooltip?.rows, ["730 tok", "4 req", "Top model gpt-4o-mini", "1 err"])
        XCTAssertEqual(nodeHoverState.nodeOpacity(nodeID: "gw_core"), 1)
        XCTAssertEqual(nodeHoverState.nodeOpacity(nodeID: "pv_anthropic"), 0.38)
        XCTAssertEqual(nodeHoverState.edgeOpacity(edgeID: "gw_core->pv_openai", segmentID: "gw_core->pv_openai#gpt-4o-mini"), 1)
        XCTAssertEqual(nodeHoverState.edgeOpacity(edgeID: "gw_aux->pv_anthropic", segmentID: "gw_aux->pv_anthropic#gemini-2.5-pro"), 0.16)
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

    func testCompactLogRowSummaryFormatting() {
        let log = AdminLog(
            requestID: "req_compact",
            gatewayID: "gw",
            providerID: "pv",
            model: "gpt-5",
            inboundProtocol: "openai",
            upstreamProtocol: "anthropic",
            modelRequested: "gpt-5-codex",
            modelEffective: "gpt-5",
            statusCode: 502,
            latencyMs: 1820,
            stream: true,
            firstByteMs: 420,
            inputTokens: 1200,
            outputTokens: 640,
            cachedTokens: 300,
            totalTokens: 2140,
            errorStage: "upstream_response",
            errorType: "upstream_error",
            error: "provider timeout",
            createdAt: "2026-03-03T10:00:00Z"
        )

        let model = LogStreamCardModel.make(log: log)

        XCTAssertEqual(model.summaryText, "provider timeout")
        XCTAssertEqual(model.secondaryMetaText, "Tok 1.2k in / 640 out / 300 c")
        XCTAssertEqual(model.metaBadges, ["1820 ms", "10:00:00", "openai -> anthropic", "Streaming"])
    }

    func testExpandedDiagnosticsGrouping() {
        let log = AdminLog(
            requestID: "req_expand",
            gatewayID: "gw",
            providerID: "pv",
            model: "gpt-5",
            inboundProtocol: "openai",
            upstreamProtocol: "openai",
            statusCode: 500,
            latencyMs: 980,
            stream: false,
            firstByteMs: 210,
            inputTokens: 880,
            outputTokens: 140,
            cachedTokens: 320,
            totalTokens: 1340,
            usageJSON: "",
            errorStage: "upstream_response",
            errorType: "provider_error",
            error: "bad gateway",
            createdAt: "2026-03-03T10:00:00Z"
        )

        let model = LogStreamCardModel.make(log: log)

        XCTAssertEqual(model.executionDetails.map(\.label), ["Request ID", "Protocol", "Stream", "First Byte"])
        XCTAssertEqual(model.executionDetails.map(\.value), ["req_expand", "openai -> openai", "Non-stream", "210 ms"])
        XCTAssertEqual(model.diagnosticsDetails.map(\.label), ["Tokens", "Error Stage", "Error Type", "Error"])
        XCTAssertEqual(model.diagnosticsDetails.first?.value, "In 880 · Out 140 · Cached 320 · Total 1340")
        XCTAssertNil(model.usageText)
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
              "cached_tokens": 300,
              "by_model": [
                {
                  "model": "gpt-5-codex",
                  "total_tokens": 700,
                  "input_tokens": 320,
                  "output_tokens": 340,
                  "cached_tokens": 40,
                  "request_count": 3,
                  "error_count": 1
                },
                {
                  "model": "gpt-4o-mini",
                  "total_tokens": 600,
                  "input_tokens": 480,
                  "output_tokens": 120,
                  "cached_tokens": 0,
                  "request_count": 9,
                  "error_count": 0
                }
              ]
            },
            {
              "timestamp": "2026-03-11 10:05:00",
              "request_count": 18,
              "avg_latency": 240,
              "error_count": 3,
              "input_tokens": 1000,
              "output_tokens": 1800,
              "cached_tokens": 500,
              "by_model": [
                {
                  "model": "gpt-5-codex",
                  "total_tokens": 1900,
                  "input_tokens": 700,
                  "output_tokens": 1100,
                  "cached_tokens": 100,
                  "request_count": 8,
                  "error_count": 2
                }
              ]
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
        XCTAssertEqual(trend.data.first?.byModel.count, 2)
        XCTAssertEqual(trend.data.first?.byModel.first?.model, "gpt-5-codex")
        XCTAssertEqual(trend.data.first?.byModel.first?.totalTokens, 700)
        XCTAssertEqual(trend.data.first?.byModel.first?.requestCount, 3)
        XCTAssertEqual(trend.data.last?.byModel.first?.cachedTokens, 100)
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
            totalCachedTokens: 0,
            tokenTrendSeries: [],
            tokenTrendBuckets: [],
            tokenTrendSummaryItems: []
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

    func testTrafficMonitorBuildsTokenTrendSeriesAndSummary() {
        let overview = AdminStatsOverview(
            totalRequests: 20,
            successfulRequests: 11,
            errorRequests: 9,
            successRate: 55.0,
            requestsPerMinute: 0.3,
            totalTokens: 2_000,
            cachedTokens: 120,
            byGateway: [],
            byProvider: [],
            byModel: [
                AdminModelStats(
                    model: "gpt-5-codex",
                    requestCount: 8,
                    successCount: 6,
                    errorCount: 2,
                    totalTokens: 800,
                    cachedTokens: 80,
                    avgLatency: 420
                )
            ]
        )
        let trend = AdminStatsTrend(
            period: "1h",
            interval: "5m",
            data: [
                AdminStatsTrendPoint(
                    timestamp: "2026-03-11 10:00:00",
                    requestCount: 9,
                    avgLatency: 300,
                    errorCount: 2,
                    inputTokens: 400,
                    outputTokens: 500,
                    cachedTokens: 100,
                    byModel: [
                        .init(model: "gpt-5-codex", totalTokens: 500, inputTokens: 200, outputTokens: 250, cachedTokens: 50, requestCount: 5, errorCount: 1),
                        .init(model: "gpt-4o-mini", totalTokens: 200, inputTokens: 80, outputTokens: 110, cachedTokens: 10, requestCount: 2, errorCount: 0),
                        .init(model: "claude-sonnet", totalTokens: 100, inputTokens: 40, outputTokens: 55, cachedTokens: 5, requestCount: 1, errorCount: 0),
                        .init(model: "o3-mini", totalTokens: 50, inputTokens: 20, outputTokens: 25, cachedTokens: 5, requestCount: 1, errorCount: 0),
                        .init(model: "gemini-2.0", totalTokens: 150, inputTokens: 60, outputTokens: 70, cachedTokens: 20, requestCount: 1, errorCount: 1)
                    ]
                ),
                AdminStatsTrendPoint(
                    timestamp: "2026-03-11 10:05:00",
                    requestCount: 11,
                    avgLatency: 450,
                    errorCount: 7,
                    inputTokens: 700,
                    outputTokens: 250,
                    cachedTokens: 20,
                    byModel: [
                        .init(model: "gpt-5-codex", totalTokens: 300, inputTokens: 110, outputTokens: 170, cachedTokens: 20, requestCount: 3, errorCount: 1),
                        .init(model: "gpt-4o-mini", totalTokens: 300, inputTokens: 140, outputTokens: 150, cachedTokens: 10, requestCount: 3, errorCount: 2),
                        .init(model: "claude-sonnet", totalTokens: 200, inputTokens: 120, outputTokens: 75, cachedTokens: 5, requestCount: 2, errorCount: 1),
                        .init(model: "o3-mini", totalTokens: 200, inputTokens: 130, outputTokens: 65, cachedTokens: 5, requestCount: 3, errorCount: 3)
                    ]
                )
            ]
        )

        let model = TrafficAnalyticsModel.make(
            overview: overview,
            trend: trend,
            selectedPeriod: "1h"
        )

        XCTAssertEqual(
            model.tokenTrendSeries.map(\.modelName),
            ["gpt-5-codex", "gpt-4o-mini", "claude-sonnet", "o3-mini", "Other"]
        )
        XCTAssertEqual(model.tokenTrendSeries[0].bucketValues, [500, 300])
        XCTAssertEqual(model.tokenTrendSeries[4].bucketValues, [150, 0])
        XCTAssertEqual(
            model.tokenTrendSummaryItems,
            [
                TrafficTrendSummaryItem(title: "Peak Total Tokens", value: "1,000"),
                TrafficTrendSummaryItem(title: "Top Model Share", value: "gpt-5-codex 40.0%"),
                TrafficTrendSummaryItem(title: "Peak Bucket Errors", value: "7")
            ]
        )
        XCTAssertEqual(
            model.tokenTrendBuckets[0].rows.map(\.modelName),
            ["gpt-5-codex", "gpt-4o-mini", "Other", "claude-sonnet", "o3-mini"]
        )
    }

    func testTrafficMonitorGroupsTailModelsIntoOtherForTokenTrend() {
        let overview = AdminStatsOverview(
            totalRequests: 5,
            successfulRequests: 5,
            errorRequests: 0,
            successRate: 100.0,
            requestsPerMinute: 0.1,
            totalTokens: 720,
            byGateway: [],
            byProvider: [],
            byModel: []
        )
        let trend = AdminStatsTrend(
            period: "1h",
            interval: "5m",
            data: [
                AdminStatsTrendPoint(
                    timestamp: "2026-03-11 10:00:00",
                    requestCount: 3,
                    avgLatency: 120,
                    errorCount: 0,
                    inputTokens: 220,
                    outputTokens: 140,
                    cachedTokens: 0,
                    byModel: [
                        .init(model: "a", totalTokens: 200, inputTokens: 100, outputTokens: 100, cachedTokens: 0, requestCount: 1, errorCount: 0),
                        .init(model: "b", totalTokens: 150, inputTokens: 70, outputTokens: 80, cachedTokens: 0, requestCount: 1, errorCount: 0),
                        .init(model: "c", totalTokens: 90, inputTokens: 45, outputTokens: 45, cachedTokens: 0, requestCount: 1, errorCount: 0),
                        .init(model: "e", totalTokens: 20, inputTokens: 10, outputTokens: 10, cachedTokens: 0, requestCount: 1, errorCount: 0)
                    ]
                ),
                AdminStatsTrendPoint(
                    timestamp: "2026-03-11 10:05:00",
                    requestCount: 2,
                    avgLatency: 140,
                    errorCount: 0,
                    inputTokens: 160,
                    outputTokens: 110,
                    cachedTokens: 0,
                    byModel: [
                        .init(model: "a", totalTokens: 40, inputTokens: 20, outputTokens: 20, cachedTokens: 0, requestCount: 1, errorCount: 0),
                        .init(model: "b", totalTokens: 110, inputTokens: 60, outputTokens: 50, cachedTokens: 0, requestCount: 1, errorCount: 0),
                        .init(model: "c", totalTokens: 30, inputTokens: 15, outputTokens: 15, cachedTokens: 0, requestCount: 1, errorCount: 0),
                        .init(model: "d", totalTokens: 80, inputTokens: 40, outputTokens: 40, cachedTokens: 0, requestCount: 1, errorCount: 0)
                    ]
                )
            ]
        )

        let model = TrafficAnalyticsModel.make(
            overview: overview,
            trend: trend,
            selectedPeriod: "1h"
        )

        XCTAssertEqual(model.tokenTrendSeries.map(\.modelName), ["b", "a", "c", "d", "Other"])
        XCTAssertEqual(model.tokenTrendSeries[3].bucketValues, [0, 80])
        XCTAssertEqual(model.tokenTrendSeries[4].bucketValues, [20, 0])
    }

    func testTrafficTrendIntervalUsesDenserBuckets() {
        XCTAssertEqual(trafficTrendInterval(for: "1h"), "1m")
        XCTAssertEqual(trafficTrendInterval(for: "6h"), "5m")
        XCTAssertEqual(trafficTrendInterval(for: "24h"), "15m")
        XCTAssertEqual(trafficTrendInterval(for: "unexpected"), "5m")
    }

    func testTrafficTrendRenderableLinesUseTotalAsPrimaryAndModelRawValues() {
        let series = [
            TrafficTokenTrendSeries(modelName: "gpt-5-codex", bucketValues: [500, 300], totalTokens: 800),
            TrafficTokenTrendSeries(modelName: "gpt-4o-mini", bucketValues: [200, 300], totalTokens: 500),
            TrafficTokenTrendSeries(modelName: "Other", bucketValues: [150, 0], totalTokens: 150)
        ]
        let buckets = [
            TrafficTokenTrendBucket(timestamp: "2026-03-11 10:00:00", totalTokens: 850, errorCount: 2, rows: []),
            TrafficTokenTrendBucket(timestamp: "2026-03-11 10:05:00", totalTokens: 600, errorCount: 7, rows: [])
        ]

        let lines = buildTrafficTrendRenderableLines(series: series, buckets: buckets)

        XCTAssertEqual(
            lines,
            [
                TrafficTrendRenderableLine(name: "Total Tokens", values: [850, 600], style: .total),
                TrafficTrendRenderableLine(name: "gpt-5-codex", values: [500, 300], style: .model),
                TrafficTrendRenderableLine(name: "gpt-4o-mini", values: [200, 300], style: .model),
                TrafficTrendRenderableLine(name: "Other", values: [150, 0], style: .model)
            ]
        )
    }

    func testTrafficTrendSmoothingSegmentsKeepEndpointsAndClampControlPoints() {
        let peakPoints = [
            CGPoint(x: 0, y: 84),
            CGPoint(x: 60, y: 18),
            CGPoint(x: 120, y: 82)
        ]

        let peakSegments = buildTrafficTrendSmoothingSegments(points: peakPoints, tension: 0.42)

        XCTAssertEqual(peakSegments.count, 2)
        XCTAssertEqual(peakSegments[0].start, peakPoints[0])
        XCTAssertEqual(peakSegments[0].end, peakPoints[1])
        XCTAssertEqual(peakSegments[1].start, peakPoints[1])
        XCTAssertEqual(peakSegments[1].end, peakPoints[2])

        for segment in peakSegments {
            let localMinY = min(segment.start.y, segment.end.y)
            let localMaxY = max(segment.start.y, segment.end.y)
            XCTAssertGreaterThanOrEqual(segment.control1.y, localMinY)
            XCTAssertLessThanOrEqual(segment.control1.y, localMaxY)
            XCTAssertGreaterThanOrEqual(segment.control2.y, localMinY)
            XCTAssertLessThanOrEqual(segment.control2.y, localMaxY)
        }

        let plateauPoints = [
            CGPoint(x: 0, y: 42),
            CGPoint(x: 50, y: 42),
            CGPoint(x: 100, y: 42)
        ]

        let plateauSegments = buildTrafficTrendSmoothingSegments(points: plateauPoints, tension: 0.42)

        XCTAssertEqual(plateauSegments.count, 2)
        XCTAssertEqual(plateauSegments[0].control1.y, 42, accuracy: 0.001)
        XCTAssertEqual(plateauSegments[0].control2.y, 42, accuracy: 0.001)
        XCTAssertEqual(plateauSegments[1].control1.y, 42, accuracy: 0.001)
        XCTAssertEqual(plateauSegments[1].control2.y, 42, accuracy: 0.001)
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

    private func makeSankeyFixtureGraph() -> TopologyGraph {
        TopologyGraph.make(
            gateways: [
                AdminGateway(
                    id: "gw_core",
                    name: "Core Gateway",
                    listenHost: "127.0.0.1",
                    listenPort: 18080,
                    inboundProtocol: "openai",
                    defaultProviderId: "pv_openai",
                    enabled: true,
                    autoStart: true,
                    runtimeStatus: "running",
                    lastError: nil
                ),
                AdminGateway(
                    id: "gw_aux",
                    name: "Aux Gateway",
                    listenHost: "127.0.0.1",
                    listenPort: 18081,
                    inboundProtocol: "openai",
                    defaultProviderId: "pv_anthropic",
                    enabled: true,
                    autoStart: true,
                    runtimeStatus: "running",
                    lastError: nil
                )
            ],
            providers: [
                AdminProvider(
                    id: "pv_openai",
                    name: "OpenAI",
                    kind: "openai",
                    baseURL: "https://api.openai.com/v1",
                    apiKey: "sk-openai",
                    models: ["gpt-4o-mini", "claude-3-7-sonnet"],
                    enabled: true
                ),
                AdminProvider(
                    id: "pv_anthropic",
                    name: "Anthropic",
                    kind: "anthropic",
                    baseURL: "https://api.anthropic.com/v1",
                    apiKey: "sk-anthropic",
                    models: ["gemini-2.5-pro"],
                    enabled: true
                )
            ],
            logs: [
                AdminLog(requestID: "req_1", gatewayID: "gw_core", providerID: "pv_openai", model: "gpt-4o-mini", statusCode: 200, latencyMs: 120, inputTokens: 400, outputTokens: 160, cachedTokens: 6, totalTokens: 560, error: nil, createdAt: "2026-03-06T10:00:00Z"),
                AdminLog(requestID: "req_2", gatewayID: "gw_core", providerID: "pv_openai", model: "gpt-4o-mini", statusCode: 200, latencyMs: 100, inputTokens: 60, outputTokens: 20, cachedTokens: 4, totalTokens: 80, error: nil, createdAt: "2026-03-06T10:01:00Z"),
                AdminLog(requestID: "req_3", gatewayID: "gw_core", providerID: "pv_openai", model: "claude-3-7-sonnet", statusCode: 503, latencyMs: 520, inputTokens: 60, outputTokens: 30, cachedTokens: 2, totalTokens: 90, error: "upstream unavailable", createdAt: "2026-03-06T10:02:00Z"),
                AdminLog(requestID: "req_4", gatewayID: "gw_aux", providerID: "pv_anthropic", model: "gemini-2.5-pro", statusCode: 200, latencyMs: 140, inputTokens: 220, outputTokens: 90, cachedTokens: 0, totalTokens: 310, error: nil, createdAt: "2026-03-06T10:03:00Z"),
                AdminLog(requestID: "req_5", gatewayID: "gw_core", providerID: "pv_openai", model: "gpt-4o-mini", statusCode: 200, latencyMs: 90, inputTokens: 0, outputTokens: 0, cachedTokens: 0, totalTokens: 0, error: nil, createdAt: "2026-03-06T10:04:00Z")
            ]
        )
    }
}
