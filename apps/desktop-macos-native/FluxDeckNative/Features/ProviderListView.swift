import SwiftUI

struct ProviderListView: View {
    let providers: [AdminProvider]
    let isLoading: Bool
    let isSubmitting: Bool
    let error: String?
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .disabled(isSubmitting)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isLoading && providers.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading providers...")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } else if providers.isEmpty {
                EmptyStateView(
                    title: "No providers",
                    systemImage: "shippingbox",
                    message: "Create a provider to route gateway traffic."
                )
            } else {
                List(providers) { provider in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                                .fontWeight(.medium)
                            Text(provider.baseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(provider.kind.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        Text(provider.enabled ? "Enabled" : "Disabled")
                            .font(.caption2)
                            .foregroundStyle(provider.enabled ? .green : .secondary)
                    }
                }
                .listStyle(.inset)
            }

            if isSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Submitting provider...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(12)
    }
}
