# Web platform contract

## Scope

The web client is an online-session-first companion for current common browsers. It
retains a protected device identity in the browser profile so every reload does not
consume another backend device slot, but it does not claim native background delivery or
native hardware-key guarantees.

## Origin and transport

- Serve the application and APIs from the provisioned HTTPS origin where practical.
- WebSocket connects only to the configured `wss` endpoint and authenticates with the
  first in-band frame.
- Backend `ALLOWED_WS_ORIGINS` contains the exact production origins.
- No mixed content, public connectivity probe, third-party script, CDN, remote font,
  analytics, or foreign service call is permitted.

The web bundle cannot install or pin a private CA. Before the first page load, the server
operator MUST distribute the private root through a trusted out-of-band channel and the
user or managed device MUST install it in the operating-system/browser trust store. The
installation guide publishes the root fingerprint through that independent channel. A
certificate error is a blocking provisioning error with no bypass. Native SPKI pinning
does not apply to browser networking APIs.

## Local protection

- Create a non-extractable WebCrypto wrapping key and persist its `CryptoKey` handle in
  IndexedDB where browser support passes the compatibility suite.
- Persist private device state, refresh credentials, and history only as authenticated
  ciphertext under wrapped keys.
- Persist no decrypted message/search index, attachment, filename, profile, or room/group
  metadata.
- Decrypt the active session into bounded memory and clear references on logout, Forget
  This Browser, integrity failure, and page teardown where observable.
- A browser storage reset is equivalent to losing/revoking the local device. Recovery can
  restore cross-signing identity material but not browser history; a fresh browser gets
  history only from an existing online device. It registers fresh device/PQ keys through
  the two-phase enrollment flow before any history transfer or sensitive messaging.

Non-extractable means browser APIs refuse export; trusted page code can still ask the key
to decrypt. It is not a defense against malicious same-origin JavaScript.

## Browser execution

Crypto and large parsing work run in dedicated workers/Wasm and use transfer/bounded
buffers so the UI thread remains responsive. The Web build uses a reviewed Wasm build of
the same FIPS 203 ML-KEM implementation as Android and passes identical PQXDH/PQ-MLS
vectors; pure-Dart ML-KEM is forbidden. The LiveKit E2EE worker is built and hashed as
part of the release. Workers do not log or post secrets to arbitrary origins.

The page reconnects and drains on load, visibility resume, `online` events, and socket
failure. Service workers may cache the signed static application shell, but correctness
and message receipt do not depend on Background Sync because it is not consistently
available across target browsers and workers are not persistent.

## Closed/suspended behavior

When the tab is closed or suspended, the client may be unreachable. The backend queues
durable envelopes for seven days. On return, the client refreshes auth, drains, checks
`pruned_through`, decrypts, stores, and acknowledges them. A detected gap enters the
documented group-rejoin flow. The UI and documentation never promise closed-browser
notifications.

## Web hardening

- Strict hash/nonce-based Content Security Policy compatible with the compiled Flutter
  and Wasm output; `object-src 'none'`, restrictive `base-uri`, `frame-ancestors`,
  `connect-src`, `worker-src`, and no unsafe eval in production.
- HSTS, `nosniff`, strict referrer policy, restrictive permissions policy, and
  cross-origin isolation headers when required by vetted Wasm behavior.
- Subresource integrity/hash manifest for static scripts, workers, Wasm, fonts, and
  assets, with no third-party resource.
- Escape all text; message content never becomes HTML.
- Capability URLs are not put in browser history, DOM attributes longer than necessary,
  referrers, or logs.
- Production source maps are withheld from the public origin or contain no secrets; build
  mapping access is operationally controlled.

## Web distribution limitation

CSP and integrity protect against many injection paths, but the HTML root that declares
them is served by the server. A fully compromised web host can serve a malicious future
bundle. Reproducible build hashes published through an independent channel and a pinned
native client improve detection; they do not erase this architectural limitation. The
Security Notice communicates it without claiming Android-equivalent trust.

## Browser test matrix

For every supported release baseline test:

- Wasm/worker startup and cryptographic test vectors;
- IndexedDB persistence and non-extractable key structured cloning;
- private/incognito behavior and quota/storage eviction;
- WebSocket auth/reconnect and origin enforcement;
- Drift storage and migration;
- RTL, accessibility, keyboard, clipboard, downloads, camera/file picker;
- LiveKit microphone and E2EE worker;
- tab suspension, multi-tab exclusion, reload, and browser update.

Only one tab may own a device's ratchet/MLS writer lock. Other tabs use a coordination
channel or show a read-only/take-over state; concurrent independent ratchet mutation is
forbidden.

## Primary references

- [Web Cryptography API](https://www.w3.org/TR/WebCryptoAPI/)
- [MDN offline and background operation](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Offline_and_background_operation)
- [MDN Background Synchronization availability](https://developer.mozilla.org/en-US/docs/Web/API/Background_Synchronization_API)
- [MDN strict CSP guidance](https://developer.mozilla.org/en-US/docs/Web/Security/Practical_implementation_guides/CSP)
