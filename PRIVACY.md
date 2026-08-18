# Privacy and data protection

DialBridge for iOS moves a phone number from a browser to a phone. A phone
number identifies a person, so it is personal data, and this says what happens
to it.

> An engineering description written to be accurate, not legal advice. If you
> deploy this for an organisation, have a lawyer review your circumstances.

---

## The short version

The number is **encrypted in your browser** and **decrypted on your iPhone**.
Apple routes a message it cannot read. Nothing is collected, there is no
analytics and no account, and the numbers you receive are never written to
storage.

---

## What is stored, and where

| Data | Where | Why | How long |
|---|---|---|---|
| Encryption key | Shared app-group container on the phone; and in the browser | Makes the number unreadable to Apple and the relay | Until you re-pair or delete |
| APNs device token | Phone, browser, and visible to Apple and the relay | The delivery address | Until you re-pair, delete, or reinstall |
| Relay address | Phone and browser | Where to send | Until changed |
| The phone number | In transit only, encrypted; then in a notification | The entire purpose | Never written to storage |

### One decision specific to this port

The encryption key lives in the **shared app-group container**, not the
Keychain. It has to be readable by the notification service extension, which is
a separate process — without that, an arriving push cannot be decrypted and the
app is useless.

The container is protected by iOS file-level encryption and the app sandbox. A
Keychain item with a shared access group would be marginally stronger against
an attacker with a jailbroken device or a filesystem image. That is a
documented trade-off rather than an oversight, and a reasonable improvement for
anyone extending this.

---

## Who is responsible for what

**Using it yourself, for yourself.** GDPR's household exemption (Article
2(2)(c)) covers processing in the course of a purely personal activity. An
individual dialling their own contacts from their own laptop falls inside it.

**Deploying it for an organisation** makes you the controller for the numbers
your people dial and the device tokens involved, with the usual consequences: a
lawful basis, a record of processing, a privacy notice, and the rights
machinery below.

**Third parties in the chain on iOS:** Apple, unavoidably, as the carrier — the
platform permits no alternative. Plus whoever operates the relay, probably you.
Apple's involvement means the device token is transferred outside the EEA. The
number itself does not travel readably, which is the point of the encryption.

Unlike the Android app, **there is no configuration that removes the platform
vendor from the path.** If that matters to you, the Android version's own
connection is the only option in the family that offers it.

---

## Rights, and how the app supports them

**Erasure.** *Delete everything this app stores* clears the key, the token and
the relay address. In the browser, *Forget this phone* removes the pairing.
Neither leaves a copy.

**Access and portability.** Everything stored is in the table above and shown
on the app's own screen. There is no hidden profile.

**Rectification.** Generating a new pairing code replaces the key; the old
pairing stops working immediately.

---

## Security

- AES-256-GCM, a fresh 96-bit nonce per message, 128-bit tag.
- The key is generated on the phone by CryptoKit and travels only inside the
  pairing code you copy across yourself.
- Authenticated encryption means a forged message fails to decrypt rather than
  producing something misleading, so successful decryption doubles as proof the
  message came from the paired browser.
- The extension additionally refuses anything that does not decrypt to a valid
  E.164 number.
- The relay validates the token and payload shapes before contacting Apple.

**Known limits.** The device token is a delivery address, not a secret:
somebody who obtained it could cause a notification to appear, though not one
showing a number of their choosing. The pairing code *is* sensitive — it
carries the key. And nothing here defends against a compromised phone or
browser, which see the number by definition.

---

## App Store privacy declaration

The declaration matching this code:

- **Data collected:** none.
- **Data linked to the user:** none.
- **Tracking:** none.
- **Third-party SDKs:** none. The app has no dependencies beyond Apple's own
  frameworks.

Re-check this against your own build before submitting. Adding an analytics or
crash-reporting library makes the statement above untrue.

---

## Contact

Add a contact address here before distributing to anyone else.
