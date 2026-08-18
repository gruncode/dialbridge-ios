// Relay for the iOS app.
//
// Apple requires every push to come through APNs, and APNs requires a signed
// token that must not be shipped to clients — so, as on the Android Firebase
// route, a small server stands in between. This is it.
//
// No dependencies: Node speaks HTTP/2 and signs ES256 out of the box, and
// APNs needs nothing else.
//
// What it deliberately does NOT do:
//   * decrypt anything — it holds no key, and the number is ciphertext here
//   * store anything — no database, no queue, no state between requests
//   * log anything identifying — no device tokens, no payloads
//
// Configure with environment variables:
//   APNS_KEY      contents of the .p8 file from Apple (keep it secret)
//   APNS_KEY_ID   the 10-character key identifier
//   APNS_TEAM_ID  your 10-character Apple team identifier
//   APNS_TOPIC    the app's bundle id, e.g. com.gruncode.browserdial
//   APNS_ENV      "sandbox" while developing, "production" for TestFlight/App Store

const http2 = require("node:http2");
const crypto = require("node:crypto");

const MAX_PAYLOAD_CHARS = 512;
const MAX_TOKEN_CHARS = 200;

// Apple rejects tokens refreshed more often than once every 20 minutes and
// expires them after 60, so one is minted per interval and reused.
const TOKEN_LIFETIME_MS = 45 * 60 * 1000;
let cachedToken = null;
let cachedAt = 0;

function base64Url(input) {
  return Buffer.from(input).toString("base64url");
}

/** Mint the ES256 JWT that authenticates us to Apple. */
function authorisationToken() {
  const now = Date.now();
  if (cachedToken && now - cachedAt < TOKEN_LIFETIME_MS) return cachedToken;

  const header = base64Url(JSON.stringify({ alg: "ES256", kid: process.env.APNS_KEY_ID }));
  const claims = base64Url(
    JSON.stringify({ iss: process.env.APNS_TEAM_ID, iat: Math.floor(now / 1000) })
  );

  // JWT wants the raw r||s signature, not the DER encoding Node produces by
  // default — hence dsaEncoding. Getting this wrong yields a valid-looking
  // token that Apple rejects with InvalidProviderToken.
  const signature = crypto.sign(
    "sha256",
    Buffer.from(`${header}.${claims}`),
    { key: process.env.APNS_KEY, dsaEncoding: "ieee-p1363" }
  );

  cachedToken = `${header}.${claims}.${signature.toString("base64url")}`;
  cachedAt = now;
  return cachedToken;
}

/** Send one notification, resolving to Apple's status code. */
function pushToApple(deviceToken, payload) {
  const host =
    process.env.APNS_ENV === "production"
      ? "https://api.push.apple.com"
      : "https://api.sandbox.push.apple.com";

  const body = JSON.stringify({
    aps: {
      alert: {
        title: "Call this number",
        // Replaced by the notification service extension once it decrypts the
        // payload. Shown as-is only if that extension fails to run.
        body: "Incoming number"
      },
      // Without this the extension is never invoked and the placeholder is all
      // the user ever sees.
      "mutable-content": 1,
      sound: "default",
      "interruption-level": "time-sensitive"
    },
    payload
  });

  return new Promise((resolve, reject) => {
    const client = http2.connect(host);
    client.on("error", reject);

    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${authorisationToken()}`,
      "apns-topic": process.env.APNS_TOPIC,
      "apns-push-type": "alert",
      // 10 = deliver immediately. A call request that arrives late is useless.
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 120),
      "content-type": "application/json",
      "content-length": Buffer.byteLength(body)
    });

    let status = 0;
    let reason = "";

    request.on("response", (headers) => {
      status = headers[":status"];
    });
    request.setEncoding("utf8");
    request.on("data", (chunk) => {
      reason += chunk;
    });
    request.on("end", () => {
      client.close();
      resolve({ status, reason });
    });
    request.on("error", (error) => {
      client.close();
      reject(error);
    });

    request.end(body);
  });
}

// Exported for the test in test/jwt.test.js. The signature encoding is the
// easiest thing here to get subtly wrong, so it is worth testing directly.
exports._authorisationToken = authorisationToken;
exports._resetTokenCache = () => {
  cachedToken = null;
  cachedAt = 0;
};

function setCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
}

exports.relay = async (req, res) => {
  setCors(res);

  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST") return res.status(405).json({ error: "method-not-allowed" });

  const body = req.body && typeof req.body === "object" ? req.body : {};
  const { deviceToken, payload } = body;

  // APNs device tokens are hex. Anything else is not from our app.
  if (
    typeof deviceToken !== "string" ||
    deviceToken.length === 0 ||
    deviceToken.length > MAX_TOKEN_CHARS ||
    !/^[0-9a-fA-F]+$/.test(deviceToken)
  ) {
    return res.status(400).json({ error: "invalid-device-token" });
  }

  // The payload must look like our base64url ciphertext and nothing else. This
  // is what stops the relay being repurposed as a general message pipe.
  if (
    typeof payload !== "string" ||
    payload.length === 0 ||
    payload.length > MAX_PAYLOAD_CHARS ||
    !/^[A-Za-z0-9_-]+$/.test(payload)
  ) {
    return res.status(400).json({ error: "invalid-payload" });
  }

  try {
    const { status, reason } = await pushToApple(deviceToken, payload);

    if (status === 200) return res.status(202).json({ ok: true });

    // 410 means Apple has retired that token: the app was deleted or restored
    // onto another device, and the user needs to pair again.
    if (status === 410) return res.status(410).json({ error: "expired-device-token" });

    // Apple's reason strings name the fault, never the recipient, so they are
    // safe to log and genuinely useful when a deployment is misconfigured.
    console.error("APNs refused:", status, reason.slice(0, 120));
    return res.status(502).json({ error: "relay-failed" });
  } catch (error) {
    console.error("APNs unreachable:", error && error.code);
    return res.status(502).json({ error: "relay-failed" });
  }
};
