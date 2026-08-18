import UIKit

/// Hands a number to the system phone app.
///
/// Worth being precise about what this does, because it differs from the
/// Android version: `tel:` on iOS shows a system confirmation and then places
/// the call, rather than opening a keypad with the number typed in. There is
/// no public way to open the dialer pre-filled without calling — Apple does
/// not offer one.
///
/// The confirmation is the system's, not ours, and it cannot be suppressed.
/// That is a reasonable place for the decision to sit: this app never dials
/// anything without the person tapping twice.
enum Dialer {

    static func dial(_ e164: String) {
        // Strip everything a dialer would not accept. The number has already
        // been validated as E.164 by the caller; this guards against a URL
        // being built from anything unexpected.
        let digits = e164.filter { $0.isNumber || $0 == "+" }
        guard
            !digits.isEmpty,
            let url = URL(string: "tel:\(digits)"),
            UIApplication.shared.canOpenURL(url)
        else {
            return
        }
        UIApplication.shared.open(url)
    }

    /// False on iPad and iPod touch, where there is no cellular radio to dial
    /// with. Used to warn the user rather than fail silently at the last step.
    static var deviceCanCall: Bool {
        guard let url = URL(string: "tel:+10000000000") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
