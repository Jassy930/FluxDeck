import Foundation

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

struct CreateGatewayInput: Encodable {
    let id: String
    let name: String
    let listenHost: String
    let listenPort: Int
    let inboundProtocol: String
    let defaultProviderId: String
    let defaultModel: String?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case listenHost = "listen_host"
        case listenPort = "listen_port"
        case inboundProtocol = "inbound_protocol"
        case defaultProviderId = "default_provider_id"
        case defaultModel = "default_model"
        case enabled
    }
}

private struct AdminActionResponse: Decodable {
    let ok: Bool
}

struct AdminProvider: Decodable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let baseURL: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case baseURL = "base_url"
        case enabled
    }
}

struct AdminGateway: Decodable, Identifiable {
    let id: String
    let name: String
    let listenHost: String
    let listenPort: Int
    let inboundProtocol: String
    let defaultProviderId: String
    let enabled: Bool
    let runtimeStatus: String?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case listenHost = "listen_host"
        case listenPort = "listen_port"
        case inboundProtocol = "inbound_protocol"
        case defaultProviderId = "default_provider_id"
        case enabled
        case runtimeStatus = "runtime_status"
        case lastError = "last_error"
    }
}

struct AdminLog: Decodable, Identifiable {
    let requestID: String
    let gatewayID: String
    let providerID: String
    let model: String?
    let statusCode: Int
    let latencyMs: Int
    let error: String?
    let createdAt: String

    var id: String { requestID }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case gatewayID = "gateway_id"
        case providerID = "provider_id"
        case model
        case statusCode = "status_code"
        case latencyMs = "latency_ms"
        case error
        case createdAt = "created_at"
    }
}

struct AdminApiClient {
    let baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL = URL(string: "http://127.0.0.1:7777")!, session: URLSession = .shared) {
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
        let data = try await get(path: "/admin/logs")
        return try Self.decodeLogs(from: data)
    }

    func createProvider(_ input: CreateProviderInput) async throws -> AdminProvider {
        let data = try await post(path: "/admin/providers", body: input)
        return try JSONDecoder().decode(AdminProvider.self, from: data)
    }

    func createGateway(_ input: CreateGatewayInput) async throws -> AdminGateway {
        let data = try await post(path: "/admin/gateways", body: input)
        return try JSONDecoder().decode(AdminGateway.self, from: data)
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
        try JSONDecoder().decode([AdminLog].self, from: data)
    }

    private func get(path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func post(path: String, body: some Encodable) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private struct EmptyRequest: Encodable {}

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
        let errorMatched = !errorsOnly || log.statusCode >= 400
        return gatewayMatched && providerMatched && statusMatched && errorMatched
    }
}
