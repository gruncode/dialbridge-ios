import Foundation

/// Everything the app stores, and the pairing code it hands to the browser.
///
/// Storage is the shared app-group container, because the notification
/// extension is a separate process and needs the same key. See PRIVACY.md for
/// the trade-off that choice represents.
enum Pairing {

    /// Must match the App Group in both targets' entitlements.
    static let appGroup = "group.com.gruncode.browserdial"

    private enum Key {
        static let secret = "secret"        // AES key, base64url
        static let deviceToken = "apnsToken"
        static let relay = "relay"
    }

    private static var store: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static var secret: String {
        get { store?.string(forKey: Key.secret) ?? "" }
        set { store?.set(newValue, forKey: Key.secret) }
    }

    static var deviceToken: String {
        get { store?.string(forKey: Key.deviceToken) ?? "" }
        set { store?.set(newValue, forKey: Key.deviceToken) }
    }

    static var relay: String {
        get { store?.string(forKey: Key.relay) ?? "" }
        set { store?.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.relay) }
    }

    static var isPaired: Bool {
        !secret.isEmpty && !deviceToken.isEmpty && !relay.isEmpty
    }

    /// The right to erasure, as a function. Removes every stored value.
    static func wipe() {
        guard let store else { return }
        [Key.secret, Key.deviceToken, Key.relay].forEach(store.removeObject(forKey:))
    }

    /// Build the code the browser extension expects.
    ///
    /// Identical format to the Android app's, so one extension serves both
    /// platforms: base64url of a small JSON object carrying the transport, the
    /// delivery address and the key.
    static func code() -> String? {
        guard isPaired else { return nil }

        let fields: [String: Any] = [
            "v": 1,
            "t": "apns",
            "r": relay,
            "d": deviceToken,
            "k": secret
        ]

        guard
            let json = try? JSONSerialization.data(withJSONObject: fields),
            !json.isEmpty
        else {
            return nil
        }
        return json.base64URLEncodedString()
    }

    /// Start a new pairing: a fresh key invalidates whatever the browser holds.
    static func regenerate() {
        secret = Crypto.newKey()
    }
}
