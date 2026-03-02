import SwiftUI

struct GatewayListView: View {
    let gateways: [AdminGateway]
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gateways")
                .font(.headline)

            if let error {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
            }

            if gateways.isEmpty {
                Text("No gateways")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(gateways) { gateway in
                    let status = gateway.runtimeStatus ?? "unknown"
                    let suffix = gateway.lastError.map { " error=\($0)" } ?? ""
                    Text("\(gateway.name) @ \(gateway.listenHost):\(gateway.listenPort) [\(status)]\(suffix)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
