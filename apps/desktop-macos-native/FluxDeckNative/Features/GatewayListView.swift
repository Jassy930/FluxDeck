import SwiftUI

struct GatewayListView: View {
    let gateways: [AdminGateway]
    let isLoading: Bool
    let isSubmitting: Bool
    let error: String?
    let onCreate: () -> Void
    let onToggleRuntime: (AdminGateway) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gateways")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    onCreate()
                } label: {
                    Label("New Gateway", systemImage: "plus")
                }
                .disabled(isSubmitting)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isLoading && gateways.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading gateways...")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } else if gateways.isEmpty {
                EmptyStateView(
                    title: "No gateways",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    message: "Create and start a gateway to expose the OpenAI-compatible endpoint."
                )
            } else {
                List(gateways) { gateway in
                    let category = runtimeCategory(for: gateway)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(gateway.name)
                                .fontWeight(.medium)
                            Spacer()
                            Text(category.rawValue.uppercased())
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial)
                                .foregroundStyle(color(for: category))
                                .clipShape(Capsule())
                        }

                        Text("\(gateway.listenHost):\(gateway.listenPort) · provider=\(gateway.defaultProviderId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let lastError = gateway.lastError, !lastError.isEmpty {
                            Text("Last error: \(lastError)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        HStack {
                            Spacer()
                            Button {
                                onToggleRuntime(gateway)
                            } label: {
                                Label(
                                    actionText(for: category),
                                    systemImage: category == .running ? "stop.circle" : "play.circle"
                                )
                            }
                            .buttonStyle(.borderless)
                            .disabled(isSubmitting)
                        }
                    }
                }
                .listStyle(.inset)
            }

            if isSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Applying gateway action...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for category: GatewayRuntimeCategory) -> Color {
        switch category {
        case .running:
            return .green
        case .stopped:
            return .gray
        case .error:
            return .red
        case .unknown:
            return .secondary
        }
    }

    private func actionText(for category: GatewayRuntimeCategory) -> String {
        category == .running ? "Stop" : "Start"
    }
}
