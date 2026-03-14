import SwiftUI

struct ProviderListView: View {
    let providers: [AdminProvider]
    let providerHealthStates: [AdminProviderHealthState]
    let isLoading: Bool
    let isSubmitting: Bool
    let error: String?
    let onCreate: () -> Void
    let onConfigure: (AdminProvider) -> Void
    let onToggleEnabled: (AdminProvider) -> Void
    let onProbe: (AdminProvider) -> Void
    let onDelete: (AdminProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Providers")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    onCreate()
                } label: {
                    Label("New Provider", systemImage: "plus")
                }
                .focusable(false)
                .disabled(isSubmitting)
            }

            if let error {
                SurfaceCard {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.statusColors.error.fill)
                }
            }

            if isLoading && providers.isEmpty {
                SurfaceCard {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading providers...")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .font(.caption)
                }
            } else if providers.isEmpty {
                EmptyStateView(
                    title: "No providers",
                    systemImage: "shippingbox",
                    message: "Create a provider to route gateway traffic."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(providers) { provider in
                            let card = ProviderWorkspaceCard.make(
                                provider: provider,
                                healthStates: providerHealthStates
                            )

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
                                        StatusPill(
                                            text: card.kindBadge,
                                            semanticColor: DesignTokens.statusColors.warning
                                        )
                                    }

                                    resourceRow(label: "Endpoint", value: card.endpointText)
                                    resourceRow(label: "Models", value: card.modelCountText)
                                    resourceRow(label: "Health", value: card.healthStatusText)

                                    if let healthDetail = card.healthDetailText, !healthDetail.isEmpty {
                                        resourceRow(label: "Last Failure", value: healthDetail)
                                    }

                                    StatusPill(
                                        text: card.statusText,
                                        semanticColor: provider.enabled ? DesignTokens.statusColors.running : DesignTokens.statusColors.inactive
                                    )

                                    StatusPill(
                                        text: card.healthStatusText,
                                        semanticColor: healthColor(for: card.healthStatusText)
                                    )

                                    HStack(spacing: 12) {
                                        Button("Configure") {
                                            onConfigure(provider)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.textPrimary)
                                        .disabled(isSubmitting)

                                        Button(provider.enabled ? "Disable" : "Enable") {
                                            onToggleEnabled(provider)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .disabled(isSubmitting)

                                        Button("Probe") {
                                            onProbe(provider)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.statusColors.warning.fill)
                                        .disabled(isSubmitting)

                                        Button("Delete") {
                                            onDelete(provider)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.statusColors.error.fill)
                                        .disabled(isSubmitting)
                                    }
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
                        Text("Submitting provider...")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func healthColor(for status: String) -> DesignTokens.SemanticColor {
        switch status.lowercased() {
        case "degraded":
            return DesignTokens.statusColors.warning
        case "unhealthy":
            return DesignTokens.statusColors.error
        case "probing":
            return DesignTokens.statusColors.warning
        default:
            return DesignTokens.statusColors.running
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        SurfaceCard {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(12)
        }
    }
}
