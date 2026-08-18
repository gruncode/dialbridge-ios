import UserNotifications

/// Decrypts the number before iOS shows it.
///
/// This extension is the heart of the iOS port. On Android the app itself is
/// woken and can do the work; on iOS an app cannot run in the background at
/// all, so the only code that gets a chance to touch an incoming push before
/// the user sees it is a notification service extension.
///
/// The push therefore arrives carrying ciphertext and a placeholder body. This
/// runs, decrypts, and rewrites the body to the actual number. If it fails, or
/// if iOS declines to run it under memory pressure, the placeholder is what
/// the user sees — which is the correct failure mode: uninformative rather
/// than wrong.
final class NotificationService: UNNotificationServiceExtension {

    private var handler: ((UNNotificationContent) -> Void)?
    private var draft: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.handler = contentHandler
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
        self.draft = content

        guard let content else {
            contentHandler(request.content)
            return
        }

        guard
            let payload = request.content.userInfo["payload"] as? String,
            !Pairing.secret.isEmpty,
            let number = Crypto.decrypt(payload: payload, keyBase64URL: Pairing.secret),
            Crypto.looksLikePhoneNumber(number)
        else {
            // Not ours, forged, or paired with a key we have since replaced.
            content.body = NSLocalizedString(
                "Could not read this request",
                comment: "Shown when a push fails to decrypt"
            )
            contentHandler(content)
            return
        }

        content.body = number
        // Carried through so the app knows what to dial when the user taps.
        content.userInfo["number"] = number
        contentHandler(content)
    }

    /// iOS gives the extension a few seconds; this fires if it runs out.
    override func serviceExtensionTimeWillExpire() {
        if let handler, let draft {
            handler(draft)
        }
    }
}
