import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FluxDeck Native Shell")
                .font(.title2)
            Text("Connected to fluxd Admin API")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 360)
    }
}

#Preview {
    ContentView()
}
