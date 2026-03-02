import SwiftUI

struct ContentView: View {
    @State private var providers: [AdminProvider] = []
    @State private var gateways: [AdminGateway] = []
    @State private var loadError: String?
    private let client = AdminApiClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FluxDeck Native Shell")
                .font(.title2)
            Text("Connected to fluxd Admin API")
                .foregroundStyle(.secondary)
            Divider()
            ProviderListView(providers: providers, error: loadError)
            Divider()
            GatewayListView(gateways: gateways, error: loadError)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 360)
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        do {
            async let providerTask = client.fetchProviders()
            async let gatewayTask = client.fetchGateways()
            providers = try await providerTask
            gateways = try await gatewayTask
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
