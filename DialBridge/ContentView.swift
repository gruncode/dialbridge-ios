import SwiftUI

/// The only screen: set the relay, generate a pairing code, copy it to the
/// browser — and delete everything when the user wants to.
struct ContentView: View {

    @State private var relay = Pairing.relay
    @State private var pairingCode = Pairing.code()
    @State private var registered = !Pairing.deviceToken.isEmpty
    @State private var showingDeleteConfirmation = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Click a phone number in your computer's browser and this phone offers to call it. Paste the pairing code below into the browser extension.")
                        .font(.callout)
                }

                Section("Relay") {
                    TextField("https://your-relay.example.com", text: $relay)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        // The two-parameter closure is iOS 17+; this project
                        // targets 16, where onChange passes only the new value.
                        .onChange(of: relay) { newValue in
                            Pairing.relay = newValue
                            refresh()
                        }
                    Text("Apple requires every push to come through its own service, so this route needs a small server of yours. See the project README.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Push registration") {
                    Label(
                        registered ? "Registered with Apple" : "Not registered yet",
                        systemImage: registered ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(registered ? .green : .orange)

                    if !registered {
                        Text("Push registration does not work in the simulator, and needs the push entitlement on a real device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Pairing code") {
                    Button("Generate pairing code") {
                        Pairing.regenerate()
                        refresh()
                    }

                    if let pairingCode {
                        Text(pairingCode)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(4)

                        Button(copied ? "Copied" : "Copy pairing code") {
                            UIPasteboard.general.string = pairingCode
                            copied = true
                        }

                        Text("This contains your encryption key. Treat it like a password, and generate a new one to revoke a computer's access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Fill in the relay address and wait for push registration, then generate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !Dialer.deviceCanCall {
                    Section {
                        Label(
                            "This device cannot place calls, so numbers will arrive but not dial.",
                            systemImage: "phone.down"
                        )
                        .font(.caption)
                    }
                }

                Section("Privacy") {
                    Text("This app stores a relay address, a push token and an encryption key. It never stores the numbers you are sent, and there is no analytics of any kind.")
                        .font(.caption)

                    Button("Delete everything this app stores", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("DialBridge")
        }
        .onReceive(NotificationCenter.default.publisher(for: .pairingChanged)) { _ in
            refresh()
        }
        .confirmationDialog(
            "Delete everything?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Pairing.wipe()
                relay = ""
                refresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the pairing, the encryption key and the relay address. Your browser will no longer reach this phone until you pair again.")
        }
    }

    private func refresh() {
        registered = !Pairing.deviceToken.isEmpty
        pairingCode = Pairing.code()
        copied = false
    }
}

#Preview {
    ContentView()
}
