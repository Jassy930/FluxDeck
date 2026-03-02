import Foundation

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

    static func decodeProviders(from data: Data) throws -> [AdminProvider] {
        try JSONDecoder().decode([AdminProvider].self, from: data)
    }

    static func decodeGateways(from data: Data) throws -> [AdminGateway] {
        try JSONDecoder().decode([AdminGateway].self, from: data)
    }

    private func get(path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
