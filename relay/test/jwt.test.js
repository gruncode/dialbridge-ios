// Checks the APNs authorisation token, which is the part of the relay most
// likely to be subtly wrong: a JWT signed with a DER-encoded signature looks
// perfectly valid until Apple rejects every push with InvalidProviderToken.
//
// Run with: node test/jwt.test.js

const assert = require("assert");
const crypto = require("node:crypto");

// A throwaway P-256 key pair, generated per run. Apple's real key is a .p8
// file of exactly this shape.
const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", {
  namedCurve: "prime256v1",
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" }
});

process.env.APNS_KEY = privateKey;
process.env.APNS_KEY_ID = "ABCDE12345";
process.env.APNS_TEAM_ID = "TEAM123456";
process.env.APNS_TOPIC = "com.gruncode.dialbridge";

const relay = require("../index.js");

const token = relay._authorisationToken();
const [headerPart, claimsPart, signaturePart] = token.split(".");

const header = JSON.parse(Buffer.from(headerPart, "base64url").toString());
const claims = JSON.parse(Buffer.from(claimsPart, "base64url").toString());
const signature = Buffer.from(signaturePart, "base64url");

assert.strictEqual(header.alg, "ES256", "Apple only accepts ES256");
assert.strictEqual(header.kid, "ABCDE12345", "key id must be in the header");
assert.strictEqual(claims.iss, "TEAM123456", "team id must be the issuer");
assert.ok(typeof claims.iat === "number", "issued-at must be present");
console.log("  ok   header and claims are what Apple expects");

// The signature must be raw r||s, which for P-256 is exactly 64 bytes. A DER
// signature would be ~70 and variable in length — the failure this test exists
// to catch.
assert.strictEqual(signature.length, 64, `expected 64-byte r||s, got ${signature.length}`);
console.log("  ok   signature is raw r||s, 64 bytes (not DER)");

const verified = crypto.verify(
  "sha256",
  Buffer.from(`${headerPart}.${claimsPart}`),
  { key: publicKey, dsaEncoding: "ieee-p1363" },
  signature
);
assert.ok(verified, "signature does not verify against the public key");
console.log("  ok   signature verifies");

// A second call inside the cache window must reuse the token: Apple rejects
// providers that mint them more often than once every 20 minutes.
assert.strictEqual(relay._authorisationToken(), token, "token should be cached");
console.log("  ok   token is reused rather than re-minted");

console.log("\nAll tests passed.");
