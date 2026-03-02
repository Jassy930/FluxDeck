import SwiftUI

struct ProviderListView: View {
    let providers: [AdminProvider]
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Providers")
                .font(.headline)

            if let error {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
            }

            if providers.isEmpty {
                Text("No providers")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(providers) { provider in
                    Text("\(provider.name) (\(provider.kind))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
