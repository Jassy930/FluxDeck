import Foundation

let defaultAdminBaseURL = "http://127.0.0.1:7777"

indirect enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    static func parseObject(from raw: String) throws -> [String: JSONValue] {
        let data = Data(raw.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode([String: JSONValue].self, from: data)
    }

    static func prettyPrinted(_ value: [String: JSONValue]) -> String {
        guard
            let data = try? JSONEncoder().encode(value),
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: prettyData, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }
}

enum GatewayRuntimeCategory: String {
    case running
    case stopped
    case error
    case unknown
}

struct DashboardMetrics: Equatable {
    let providerCount: Int
    let gatewayCount: Int
    let runningGatewayCount: Int
    let errorGatewayCount: Int
}

enum ProviderKindOption: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case openAIResponse = "openai-response"
    case gemini = "gemini"
    case anthropic = "anthropic"
    case azureOpenAI = "azure-openai"
    case newAPI = "new-api"
    case ollama = "ollama"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .openAIResponse:
            return "OpenAI-Response"
        case .gemini:
            return "Gemini"
        case .anthropic:
            return "Anthropic"
        case .azureOpenAI:
            return "Azure OpenAI"
        case .newAPI:
            return "New API"
        case .ollama:
            return "Ollama"
        }
    }

    var inboundProtocolSubtitle: String {
        switch self {
        case .openAI:
            return "OpenAI-compatible client ingress"
        case .openAIResponse:
            return "OpenAI Responses / Codex-style ingress"
        case .gemini:
            return "Gemini-compatible client ingress"
        case .anthropic:
            return "Anthropic messages ingress"
        case .azureOpenAI:
            return "Azure OpenAI-compatible ingress"
        case .newAPI:
            return "New API-compatible client ingress"
        case .ollama:
            return "Ollama-compatible client ingress"
        }
    }

    var upstreamProtocolSubtitle: String {
        switch self {
        case .openAI:
            return "Forward using OpenAI-compatible upstream"
        case .openAIResponse:
            return "Forward using OpenAI Responses-compatible upstream"
        case .gemini:
            return "Forward using Gemini-compatible upstream"
        case .anthropic:
            return "Forward using Anthropic upstream"
        case .azureOpenAI:
            return "Forward using Azure OpenAI-compatible upstream"
        case .newAPI:
            return "Forward using New API-compatible upstream"
        case .ollama:
            return "Forward using Ollama-compatible upstream"
        }
    }
}

struct CreateProviderInput: Encodable {
    let id: String
    let name: String
    let kind: String
    let baseURL: String
    let apiKey: String
    let models: [String]
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case baseURL = "base_url"
        case apiKey = "api_key"
        case models
        case enabled
    }
}

struct UpdateProviderInput: Encodable {
    let name: String
    let kind: String
    let baseURL: String
    let apiKey: String
    let models: [String]
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case kind
        case baseURL = "base_url"
        case apiKey = "api_key"
        case models
        case enabled
    }
}

struct CreateGatewayInput: Encodable {
    let id: String
    let name: String
    let listenHost: String
    let listenPort: Int
    let inboundProtocol: String
    let upstreamProtocol: String
    let protocolConfigJSON: [String: JSONValue]
    let defaultProviderId: String
    let defaultModel: String?
    let enabled: Bool
    let autoStart: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case listenHost = "listen_host"
        case listenPort = "listen_port"
        case inboundProtocol = "inbound_protocol"
        case upstreamProtocol = "upstream_protocol"
        case protocolConfigJSON = "protocol_config_json"
        case defaultProviderId = "default_provider_id"
        case defaultModel = "default_model"
        case enabled
        case autoStart = "auto_start"
    }
}

struct UpdateGatewayInput: Encodable {
    let name: String
    let listenHost: String
    let listenPort: Int
    let inboundProtocol: String
    let upstreamProtocol: String
    let protocolConfigJSON: [String: JSONValue]
    let defaultProviderId: String
    let defaultModel: String?
    let enabled: Bool
    let autoStart: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case listenHost = "listen_host"
        case listenPort = "listen_port"
        case inboundProtocol = "inbound_protocol"
        case upstreamProtocol = "upstream_protocol"
        case protocolConfigJSON = "protocol_config_json"
        case defaultProviderId = "default_provider_id"
        case defaultModel = "default_model"
        case enabled
        case autoStart = "auto_start"
    }
}

private struct AdminActionResponse: Decodable {
    let ok: Bool
}

struct AdminDeleteResponse: Decodable {
    let ok: Bool
    let id: String
}

struct AdminProvider: Decodable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let baseURL: String
    let apiKey: String
    let models: [String]
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case baseURL = "base_url"
        case apiKey = "api_key"
        case models
        case enabled
    }
}

struct AdminGateway: Decodable, Identifiable {
    let id: String
    let name: String
    let listenHost: String
    let listenPort: Int
    let inboundProtocol: String
    let upstreamProtocol: String
    let protocolConfigJSON: [String: JSONValue]
    let defaultProviderId: String
    let defaultModel: String?
    let enabled: Bool
    let autoStart: Bool
    let runtimeStatus: String?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case listenHost = "listen_host"
        case listenPort = "listen_port"
        case inboundProtocol = "inbound_protocol"
        case upstreamProtocol = "upstream_protocol"
        case protocolConfigJSON = "protocol_config_json"
        case defaultProviderId = "default_provider_id"
        case defaultModel = "default_model"
        case enabled
        case autoStart = "auto_start"
        case runtimeStatus = "runtime_status"
        case lastError = "last_error"
    }

    init(
        id: String,
        name: String,
        listenHost: String,
        listenPort: Int,
        inboundProtocol: String,
        upstreamProtocol: String = "provider_default",
        protocolConfigJSON: [String: JSONValue] = [:],
        defaultProviderId: String,
        defaultModel: String? = nil,
        enabled: Bool,
        autoStart: Bool,
        runtimeStatus: String?,
        lastError: String?
    ) {
        self.id = id
        self.name = name
        self.listenHost = listenHost
        self.listenPort = listenPort
        self.inboundProtocol = inboundProtocol
        self.upstreamProtocol = upstreamProtocol
        self.protocolConfigJSON = protocolConfigJSON
        self.defaultProviderId = defaultProviderId
        self.defaultModel = defaultModel
        self.enabled = enabled
        self.autoStart = autoStart
        self.runtimeStatus = runtimeStatus
        self.lastError = lastError
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        listenHost = try container.decode(String.self, forKey: .listenHost)
        listenPort = try container.decode(Int.self, forKey: .listenPort)
        inboundProtocol = try container.decode(String.self, forKey: .inboundProtocol)
        upstreamProtocol = try container.decodeIfPresent(String.self, forKey: .upstreamProtocol) ?? "provider_default"
        protocolConfigJSON = try container.decodeIfPresent([String: JSONValue].self, forKey: .protocolConfigJSON) ?? [:]
        defaultProviderId = try container.decode(String.self, forKey: .defaultProviderId)
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        runtimeStatus = try container.decodeIfPresent(String.self, forKey: .runtimeStatus)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

struct AdminGatewayUpdateResult: Decodable {
    let gateway: AdminGateway
    let runtimeStatus: String
    let lastError: String?
    let restartPerformed: Bool
    let configChanged: Bool
    let userNotice: String?

    enum CodingKeys: String, CodingKey {
        case gateway
        case runtimeStatus = "runtime_status"
        case lastError = "last_error"
        case restartPerformed = "restart_performed"
        case configChanged = "config_changed"
        case userNotice = "user_notice"
    }
}

struct AdminGatewayDeleteResult: Decodable {
    let ok: Bool
    let id: String
    let runtimeStatusBeforeDelete: String
    let stopPerformed: Bool
    let userNotice: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case id
        case runtimeStatusBeforeDelete = "runtime_status_before_delete"
        case stopPerformed = "stop_performed"
        case userNotice = "user_notice"
    }
}

struct AdminLog: Decodable, Identifiable {
    let requestID: String
    let gatewayID: String
    let providerID: String
    let model: String?
    let inboundProtocol: String?
    let upstreamProtocol: String?
    let modelRequested: String?
    let modelEffective: String?
    let statusCode: Int
    let latencyMs: Int
    let stream: Bool
    let firstByteMs: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let cachedTokens: Int?
    let totalTokens: Int?
    let usageJSON: String?
    let errorStage: String?
    let errorType: String?
    let error: String?
    let createdAt: String

    var id: String { requestID }

    var modelDisplayText: String {
        let requested = modelRequested?.nilIfEmpty
        let effective = modelEffective?.nilIfEmpty

        switch (requested, effective) {
        case let (requested?, effective?) where requested != effective:
            return "\(requested) -> \(effective)"
        case let (requested?, effective?) where requested == effective:
            return requested
        case let (requested?, nil):
            return requested
        case let (nil, effective?):
            return effective
        default:
            return model?.nilIfEmpty ?? "-"
        }
    }

    var tokenBreakdownText: String {
        var parts: [String] = []

        if let inputTokens {
            parts.append("In \(inputTokens)")
        }
        if let outputTokens {
            parts.append("Out \(outputTokens)")
        }
        if let cachedTokens {
            parts.append("Cached \(cachedTokens)")
        }
        if let totalTokens {
            parts.append("Total \(totalTokens)")
        }

        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    var errorSummaryText: String {
        if let error = error?.nilIfEmpty {
            return error
        }

        let stage = errorStage?.nilIfEmpty
        let type = errorType?.nilIfEmpty

        switch (stage, type) {
        case let (stage?, type?):
            return "\(stage) · \(type)"
        case let (stage?, nil):
            return stage
        case let (nil, type?):
            return type
        default:
            return "-"
        }
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case gatewayID = "gateway_id"
        case providerID = "provider_id"
        case model
        case inboundProtocol = "inbound_protocol"
        case upstreamProtocol = "upstream_protocol"
        case modelRequested = "model_requested"
        case modelEffective = "model_effective"
        case statusCode = "status_code"
        case latencyMs = "latency_ms"
        case stream
        case firstByteMs = "first_byte_ms"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cachedTokens = "cached_tokens"
        case totalTokens = "total_tokens"
        case usageJSON = "usage_json"
        case errorStage = "error_stage"
        case errorType = "error_type"
        case error
        case createdAt = "created_at"
    }

    init(
        requestID: String,
        gatewayID: String,
        providerID: String,
        model: String?,
        inboundProtocol: String? = nil,
        upstreamProtocol: String? = nil,
        modelRequested: String? = nil,
        modelEffective: String? = nil,
        statusCode: Int,
        latencyMs: Int,
        stream: Bool = false,
        firstByteMs: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedTokens: Int? = nil,
        totalTokens: Int? = nil,
        usageJSON: String? = nil,
        errorStage: String? = nil,
        errorType: String? = nil,
        error: String? = nil,
        createdAt: String
    ) {
        self.requestID = requestID
        self.gatewayID = gatewayID
        self.providerID = providerID
        self.model = model
        self.inboundProtocol = inboundProtocol
        self.upstreamProtocol = upstreamProtocol
        self.modelRequested = modelRequested
        self.modelEffective = modelEffective
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.stream = stream
        self.firstByteMs = firstByteMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.totalTokens = totalTokens
        self.usageJSON = usageJSON
        self.errorStage = errorStage
        self.errorType = errorType
        self.error = error
        self.createdAt = createdAt
    }

    init(
        requestID: String,
        gatewayID: String,
        providerID: String,
        model: String?,
        statusCode: Int,
        latencyMs: Int,
        error: String?,
        createdAt: String
    ) {
        self.init(
            requestID: requestID,
            gatewayID: gatewayID,
            providerID: providerID,
            model: model,
            inboundProtocol: nil,
            upstreamProtocol: nil,
            modelRequested: nil,
            modelEffective: nil,
            statusCode: statusCode,
            latencyMs: latencyMs,
            stream: false,
            firstByteMs: nil,
            inputTokens: nil,
            outputTokens: nil,
            cachedTokens: nil,
            totalTokens: nil,
            usageJSON: nil,
            errorStage: nil,
            errorType: nil,
            error: error,
            createdAt: createdAt
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(String.self, forKey: .requestID)
        gatewayID = try container.decode(String.self, forKey: .gatewayID)
        providerID = try container.decode(String.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        inboundProtocol = try container.decodeIfPresent(String.self, forKey: .inboundProtocol)
        upstreamProtocol = try container.decodeIfPresent(String.self, forKey: .upstreamProtocol)
        modelRequested = try container.decodeIfPresent(String.self, forKey: .modelRequested)
        modelEffective = try container.decodeIfPresent(String.self, forKey: .modelEffective)
        statusCode = try container.decode(Int.self, forKey: .statusCode)
        latencyMs = try container.decode(Int.self, forKey: .latencyMs)
        stream = try container.decodeIfPresent(Bool.self, forKey: .stream) ?? false
        firstByteMs = try container.decodeIfPresent(Int.self, forKey: .firstByteMs)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        cachedTokens = try container.decodeIfPresent(Int.self, forKey: .cachedTokens)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        usageJSON = try container.decodeIfPresent(String.self, forKey: .usageJSON)
        errorStage = try container.decodeIfPresent(String.self, forKey: .errorStage)
        errorType = try container.decodeIfPresent(String.self, forKey: .errorType)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }
}


struct AdminLogCursor: Decodable {
    let createdAt: String
    let requestID: String

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case requestID = "request_id"
    }
}

struct AdminLogPage: Decodable {
    let items: [AdminLog]
    let nextCursor: AdminLogCursor?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct AdminGatewayStats: Decodable, Equatable {
    let gatewayID: String
    let requestCount: Int
    let successCount: Int
    let errorCount: Int
    let totalTokens: Int
    let avgLatency: Int

    enum CodingKeys: String, CodingKey {
        case gatewayID = "gateway_id"
        case requestCount = "request_count"
        case successCount = "success_count"
        case errorCount = "error_count"
        case totalTokens = "total_tokens"
        case avgLatency = "avg_latency"
    }
}

struct AdminProviderStats: Decodable, Equatable {
    let providerID: String
    let requestCount: Int
    let successCount: Int
    let errorCount: Int
    let totalTokens: Int
    let avgLatency: Int

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case requestCount = "request_count"
        case successCount = "success_count"
        case errorCount = "error_count"
        case totalTokens = "total_tokens"
        case avgLatency = "avg_latency"
    }
}

struct AdminModelStats: Decodable, Equatable {
    let model: String
    let requestCount: Int
    let successCount: Int
    let errorCount: Int
    let totalTokens: Int
    let avgLatency: Int

    enum CodingKeys: String, CodingKey {
        case model
        case requestCount = "request_count"
        case successCount = "success_count"
        case errorCount = "error_count"
        case totalTokens = "total_tokens"
        case avgLatency = "avg_latency"
    }
}

struct AdminStatsOverview: Decodable, Equatable {
    let totalRequests: Int
    let successfulRequests: Int
    let errorRequests: Int
    let successRate: Double
    let requestsPerMinute: Double
    let totalTokens: Int
    let byGateway: [AdminGatewayStats]
    let byProvider: [AdminProviderStats]
    let byModel: [AdminModelStats]

    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case successfulRequests = "successful_requests"
        case errorRequests = "error_requests"
        case successRate = "success_rate"
        case requestsPerMinute = "requests_per_minute"
        case totalTokens = "total_tokens"
        case byGateway = "by_gateway"
        case byProvider = "by_provider"
        case byModel = "by_model"
    }
}

struct AdminStatsTrendPoint: Decodable, Equatable {
    let timestamp: String
    let requestCount: Int
    let avgLatency: Int
    let errorCount: Int
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case timestamp
        case requestCount = "request_count"
        case avgLatency = "avg_latency"
        case errorCount = "error_count"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct AdminStatsTrend: Decodable, Equatable {
    let period: String
    let interval: String
    let data: [AdminStatsTrendPoint]
}

struct AdminApiClient {
    let baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL = URL(string: defaultAdminBaseURL)!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchProviders() async throws -> [AdminProvider] {
        let data = try await get(path: "/admin/providers")
        return try Self.decodeProviders(from: data)
    }

    func fetchGateways() async throws -> [AdminGateway] {
        let data = try await get(path: "/admin/gateways")
        return try Self.decodeGateways(from: data)
    }

    func fetchLogs() async throws -> [AdminLog] {
        let page = try await fetchLogsPage(limit: 50)
        return page.items
    }

    func fetchDashboardLogs(limit: Int = 20) async throws -> [AdminLog] {
        let page = try await fetchLogsPage(limit: limit)
        return page.items
    }

    func fetchStatsOverview(period: String = "1h") async throws -> AdminStatsOverview {
        let data = try await get(
            path: "/admin/stats/overview",
            queryItems: [URLQueryItem(name: "period", value: period)]
        )
        return try Self.decodeStatsOverview(from: data)
    }

    func fetchStatsTrend(period: String = "1h", interval: String = "5m") async throws -> AdminStatsTrend {
        let data = try await get(
            path: "/admin/stats/trend",
            queryItems: [
                URLQueryItem(name: "period", value: period),
                URLQueryItem(name: "interval", value: interval)
            ]
        )
        return try Self.decodeStatsTrend(from: data)
    }

    func fetchLogsPage(
        limit: Int = 50,
        cursor: AdminLogCursor? = nil,
        gatewayID: String? = nil,
        providerID: String? = nil,
        statusCode: Int? = nil,
        errorsOnly: Bool = false
    ) async throws -> AdminLogPage {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor_created_at", value: cursor.createdAt))
            queryItems.append(URLQueryItem(name: "cursor_request_id", value: cursor.requestID))
        }
        if let gatewayID, !gatewayID.isEmpty {
            queryItems.append(URLQueryItem(name: "gateway_id", value: gatewayID))
        }
        if let providerID, !providerID.isEmpty {
            queryItems.append(URLQueryItem(name: "provider_id", value: providerID))
        }
        if let statusCode {
            queryItems.append(URLQueryItem(name: "status_code", value: String(statusCode)))
        }
        if errorsOnly {
            queryItems.append(URLQueryItem(name: "errors_only", value: "true"))
        }

        let data = try await get(path: "/admin/logs", queryItems: queryItems)
        return try Self.decodeLogPage(from: data)
    }

    func createProvider(_ input: CreateProviderInput) async throws -> AdminProvider {
        let data = try await post(path: "/admin/providers", body: input)
        return try JSONDecoder().decode(AdminProvider.self, from: data)
    }

    func updateProvider(id: String, input: UpdateProviderInput) async throws -> AdminProvider {
        let data = try await put(path: "/admin/providers/\(id)", body: input)
        return try JSONDecoder().decode(AdminProvider.self, from: data)
    }

    func deleteProvider(id: String) async throws -> AdminDeleteResponse {
        let data = try await delete(path: "/admin/providers/\(id)")
        return try JSONDecoder().decode(AdminDeleteResponse.self, from: data)
    }

    func createGateway(_ input: CreateGatewayInput) async throws -> AdminGateway {
        let data = try await post(path: "/admin/gateways", body: input)
        return try JSONDecoder().decode(AdminGateway.self, from: data)
    }

    func updateGateway(id: String, input: UpdateGatewayInput) async throws -> AdminGatewayUpdateResult {
        let data = try await put(path: "/admin/gateways/\(id)", body: input)
        return try JSONDecoder().decode(AdminGatewayUpdateResult.self, from: data)
    }

    func deleteGateway(id: String) async throws -> AdminGatewayDeleteResult {
        let data = try await delete(path: "/admin/gateways/\(id)")
        return try JSONDecoder().decode(AdminGatewayDeleteResult.self, from: data)
    }

    func startGateway(id: String) async throws {
        let data = try await post(path: "/admin/gateways/\(id)/start", body: EmptyRequest())
        let response = try JSONDecoder().decode(AdminActionResponse.self, from: data)
        guard response.ok else {
            throw URLError(.cannotParseResponse)
        }
    }

    func stopGateway(id: String) async throws {
        let data = try await post(path: "/admin/gateways/\(id)/stop", body: EmptyRequest())
        let response = try JSONDecoder().decode(AdminActionResponse.self, from: data)
        guard response.ok else {
            throw URLError(.cannotParseResponse)
        }
    }

    var displayBaseURL: String {
        baseURL.absoluteString
    }

    static func decodeProviders(from data: Data) throws -> [AdminProvider] {
        try JSONDecoder().decode([AdminProvider].self, from: data)
    }

    static func decodeGateways(from data: Data) throws -> [AdminGateway] {
        try JSONDecoder().decode([AdminGateway].self, from: data)
    }

    static func decodeLogs(from data: Data) throws -> [AdminLog] {
        try decodeLogPage(from: data).items
    }

    static func decodeLogPage(from data: Data) throws -> AdminLogPage {
        try JSONDecoder().decode(AdminLogPage.self, from: data)
    }

    static func decodeStatsOverview(from data: Data) throws -> AdminStatsOverview {
        try JSONDecoder().decode(AdminStatsOverview.self, from: data)
    }

    static func decodeStatsTrend(from data: Data) throws -> AdminStatsTrend {
        try JSONDecoder().decode(AdminStatsTrend.self, from: data)
    }

    private func get(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        return try validateResponse(data: data, response: response)
    }

    private func post(path: String, body: some Encodable) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        return try validateResponse(data: data, response: response)
    }

    private func put(path: String, body: some Encodable) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        return try validateResponse(data: data, response: response)
    }

    private func delete(path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        return try validateResponse(data: data, response: response)
    }

    private func validateResponse(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AdminAPIError.server(adminAPIErrorMessage(from: data, statusCode: http.statusCode))
        }
        return data
    }
}

private struct EmptyRequest: Encodable {}

enum AdminAPIError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        }
    }
}

func runtimeCategory(for gateway: AdminGateway) -> GatewayRuntimeCategory {
    if gateway.lastError != nil {
        return .error
    }

    switch gateway.runtimeStatus?.lowercased() {
    case "running":
        return .running
    case "stopped":
        return .stopped
    case "error":
        return .error
    default:
        return .unknown
    }
}

func buildDashboardMetrics(providers: [AdminProvider], gateways: [AdminGateway]) -> DashboardMetrics {
    let runningCount = gateways.filter { runtimeCategory(for: $0) == .running }.count
    let errorCount = gateways.filter { runtimeCategory(for: $0) == .error }.count

    return DashboardMetrics(
        providerCount: providers.count,
        gatewayCount: gateways.count,
        runningGatewayCount: runningCount,
        errorGatewayCount: errorCount
    )
}

func gatewayUpdateNoticeText(for result: AdminGatewayUpdateResult) -> String {
    if let userNotice = result.userNotice, !userNotice.isEmpty {
        return userNotice
    }
    if let lastError = result.lastError, !lastError.isEmpty {
        return "Gateway 配置已保存，但自动重启失败：\(lastError)"
    }
    if result.restartPerformed {
        return "Gateway 配置已保存，运行中的实例已自动重启。"
    }
    return "Gateway 配置已保存。"
}

func gatewayDeleteNoticeText(for result: AdminGatewayDeleteResult) -> String {
    if let userNotice = result.userNotice, !userNotice.isEmpty {
        return userNotice
    }
    if result.stopPerformed {
        return "Gateway 已删除。运行中的实例已先停止。"
    }
    return "Gateway 已删除。"
}

func adminAPIErrorMessage(from data: Data, statusCode: Int) -> String {
    if
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let error = object["error"] as? String
    {
        if let ids = object["referenced_by_gateway_ids"] as? [String], !ids.isEmpty {
            return "\(error): \(ids.joined(separator: ", "))"
        }
        return error
    }

    if let plainText = String(data: data, encoding: .utf8),
       !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return plainText
    }

    return "Request failed with HTTP \(statusCode)"
}

func filterLogs(
    _ logs: [AdminLog],
    gatewayID: String?,
    providerID: String?,
    statusCode: Int?,
    errorsOnly: Bool = false
) -> [AdminLog] {
    logs.filter { log in
        let gatewayMatched = gatewayID == nil || log.gatewayID == gatewayID
        let providerMatched = providerID == nil || log.providerID == providerID
        let statusMatched = statusCode == nil || log.statusCode == statusCode
        let errorMatched = !errorsOnly || log.statusCode >= 400 || log.error != nil
        return gatewayMatched && providerMatched && statusMatched && errorMatched
    }
}

func normalizedAdminBaseURL(_ rawValue: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
    guard let url = URL(string: candidate),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          url.host != nil
    else {
        return nil
    }

    return url
}

func recentLogs(_ logs: [AdminLog], limit: Int = 10) -> [AdminLog] {
    guard limit > 0 else {
        return []
    }

    let sorted = logs.sorted { lhs, rhs in
        let lhsDate = parseAdminLogDate(lhs.createdAt)
        let rhsDate = parseAdminLogDate(rhs.createdAt)

        switch (lhsDate, rhsDate) {
        case let (left?, right?):
            return left > right
        default:
            return lhs.createdAt > rhs.createdAt
        }
    }

    return Array(sorted.prefix(limit))
}

private func parseAdminLogDate(_ value: String) -> Date? {
    if let date = adminLogDateWithFractional.date(from: value) {
        return date
    }
    return adminLogDateWithoutFractional.date(from: value)
}

private let adminLogDateWithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let adminLogDateWithoutFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
