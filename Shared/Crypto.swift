import CryptoKit
import Foundation

/// Decryption of the number sent by the browser.
///
/// Shared between the app and the notification extension, because the
/// extension is what actually needs it: it runs when a push arrives, decrypts
/// the payload, and rewrites the notification before iOS displays it. Without
/// that, the phone would show ciphertext.
///
/// The wire format is `nonce(12) || ciphertext || tag(16)`, base64url-encoded —
/// exactly what Web Crypto's AES-GCM produces in the browser, and exactly what
/// CryptoKit calls a sealed box's `combined` representation. The two agree
/// without any translation layer, which is why this file is so short.
enum Crypto {

    /// Decrypt one message, or return nil.
    ///
    /// nil covers every failure the same way on purpose: a corrupt packet, a
    /// message forged by someone who learned the device token, and a browser
    /// still paired with a key this phone has replaced should all end in the
    /// notification being dropped, not in a crash or a misleading alert.
    static func decrypt(payload: String, keyBase64URL: String) -> String? {
        guard
            let keyData = Data(base64URLEncoded: keyBase64URL),
            keyData.count == 32,
            let packet = Data(base64URLEncoded: payload),
            packet.count > 28  // 12-byte nonce + 16-byte tag leaves nothing else
        else {
            return nil
        }

        do {
            let box = try AES.GCM.SealedBox(combined: packet)
            let opened = try AES.GCM.open(box, using: SymmetricKey(data: keyData))
            return String(data: opened, encoding: .utf8)
        } catch {
            // AES-GCM authenticates as it decrypts: a tampered or forged
            // message throws here rather than producing plausible rubbish.
            return nil
        }
    }

    /// Create the shared key. Called once, when the user generates a pairing code.
    static func newKey() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64URLEncodedString() }
    }

    /// E.164 and nothing else: an optional plus, then 6 to 15 digits.
    static func looksLikePhoneNumber(_ text: String) -> Bool {
        text.range(of: "^\\+?[0-9]{6,15}$", options: .regularExpression) != nil
    }
}

// MARK: - base64url

// Foundation only speaks standard base64. The browser, the pairing code and
// the relay all use the URL-safe alphabet without padding, so the conversion
// lives here once rather than being repeated at every call site.
extension Data {

    init?(base64URLEncoded input: String) {
        var text = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text.append("=") }
        guard let decoded = Data(base64Encoded: text) else { return nil }
        self = decoded
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
