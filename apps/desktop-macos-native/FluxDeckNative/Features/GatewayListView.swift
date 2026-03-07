import SwiftUI

struct GatewayListView: View {
    let gateways: [AdminGateway]
    let isLoading: Bool
    let isSubmitting: Bool
    let error: String?
    let onCreate: () -> Void
    let onToggleRuntime: (AdminGateway) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                SurfaceCard {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.statusColors.error.fill)
                }
            }

            if isLoading && gateways.isEmpty {
                SurfaceCard {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading gateways...")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .font(.caption)
                }
            } else if gateways.isEmpty {
                EmptyStateView(
                    title: "No gateways",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    message: "Create and start a gateway to expose the OpenAI-compatible endpoint."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(gateways) { gateway in
                            let category = runtimeCategory(for: gateway)
                            let card = GatewayWorkspaceCard.make(gateway: gateway)

                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(card.title)
                                                .font(.headline)
                                                .foregroundStyle(DesignTokens.textPrimary)
                                            Text(card.id)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(DesignTokens.textSecondary)
                                        }
                                        Spacer()
                                        StatusPill(text: card.runtimeBadge, semanticColor: colorToken(for: category))
                                    }

                                    resourceRow(label: "Endpoint", value: card.endpointText)
                                    resourceRow(label: "Provider", value: card.providerText)

                                    if let lastError = card.lastErrorText, !lastError.isEmpty {
                                        resourceRow(label: "Last Error", value: lastError)
                                    }

                                    Button {
                                        onToggleRuntime(gateway)
                                    } label: {
                                        Label(
                                            actionText(for: category),
                                            systemImage: category == .running ? "stop.circle" : "play.circle"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 10)
                                    .background(DesignTokens.surfacePrimary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                    .disabled(isSubmitting)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if isSubmitting {
                SurfaceCard {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Applying gateway action...")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorToken(for category: GatewayRuntimeCategory) -> DesignTokens.SemanticColor {
        switch category {
        case .running:
            return DesignTokens.statusColors.running
        case .stopped:
            return DesignTokens.statusColors.inactive
        case .error:
            return DesignTokens.statusColors.error
        case .unknown:
            return DesignTokens.statusColors.warning
        }
    }

    private func actionText(for category: GatewayRuntimeCategory) -> String {
        category == .running ? "Stop" : "Start"
    }

    private func resourceRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
        }
    }
}
