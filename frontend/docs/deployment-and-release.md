# Deployment and release

What the initial deployment *is* - its audience, its maturity tiers, what may be
claimed about it, and what must be disclosed - is decided by
[ADR-044](decisions.md), and what it *says* to the people who receive it - the
maturity vocabulary, the disclosure, and the one acknowledgement - is decided by
[ADR-045](decisions.md). Release signing, key custody, and upgrade-continuity
verification are specified separately in
[Beta release signing and key continuity](release-signing.md) and decided by
ADR-042. Those two are authoritative for the deployment definition and for
anything concerning signing keys, release artifacts, and their verification; this
document covers the surrounding release process.

## Environments

Use compile-time flavors with separate visible identity and trust configuration.
There are exactly three; each has one Dart entry point and reads one provisioning
prefix:

| Flavor | Entry point | Purpose | Trust |
|---|---|---|---|
| development | `lib/main_development.dart` | Local engineering | local origin/CA; debug banner |
| beta | `lib/main_beta.dart` | The Private Experimental deployment (ADR-044) | beta origin/CA/pins; persistent Beta signing identity |
| production | `lib/main_production.dart` | Future public release | production origin/private CA/primary+backup pins only |

There is deliberately no staging flavor. A fourth environment would need a fourth
application ID, a fourth provisioning prefix, and its own trust material, and
nothing in the current release process needs one: production-like integration is
rehearsed against the beta origin. Adding one is an ADR decision, not a build
edit.

Every non-production flavor carries a persistent configuration banner, on the
blocking Connection screen and inside the application shell, that names its own
build: development reads "Development configuration" and beta reads "Private
experimental build". Under ADR-044 that banner deliberately does not say "beta" -
the word overstates an unreviewed stack - even though the frozen application ID
keeps its `.beta` suffix. A beta build is installed by external testers and must
never present itself as development. Production shows no banner at all.

The banner, the Android launcher label, and the window title Android shows in the
task switcher name the same build. Before ADR-045 the title branched on production
alone, so the Private Experimental artifact called itself "Communication Platform
(Development)" beside a launcher icon reading "(Experimental)".
`AppEnvironmentBanner` now owns both strings, and the Gradle flavor owns the
launcher label they must match.

The beta and production flavors are separate, coexisting Android applications
with different application IDs and different signing identities. Neither
upgrades into the other. The production release build is deliberately unsigned
so it keeps building and stays verifiable without being installable.

No runtime text field changes the production server. Secrets are never compiled into the
client; only public origins, CA certificates, SPKI hashes, and protocol capabilities are
configuration.

## Versioning

Track independently:

- human application version;
- monotonically increasing Android version code;
- future Web artifact/build ID (post-v1);
- local database schema version;
- application-message protocol major/minor;
- crypto-state format version;
- minimum/maximum compatible backend API version when the backend exposes one in future.

The current health endpoint intentionally exposes no version, so compatibility is proved
by contract tests and conservative client behavior, not runtime version guessing.

## Dependency and toolchain control

- Pin Flutter and Dart SDKs for the team/CI.
- Commit Flutter/Dart/Rust lockfiles and checksum external artifacts.
- Mirror/cache all build dependencies so a clean release can build without international
  internet.
- Produce a version-1 SBOM covering Dart, Android/Gradle, Rust, fonts, and native
  libraries. Add Rust/Wasm and browser-worker artifacts only when Web is reopened.
- Review licenses, especially crypto libraries, before acceptance.
- Disable crypto debug/log features and remove unused architectures/resources only after
  verifying packaging rules.

## Android release

1. Build from a clean, reviewed tag in the isolated release environment.
2. Run analysis, tests, contract suite, crypto vectors, SBOM/audit, and offline-network
   rehearsal.
3. Produce deterministic release APK artifacts where the toolchain permits.
4. Sign with an offline-controlled application signing key; keep backup/recovery process
   separate from source control. The Private Experimental Beta already does this
   through `tool/build_beta_release.sh`; production keeps a distinct key that is
   not created until an explicit production release decision.
5. Generate SHA-256 artifact hashes and signed update metadata.
6. Verify install, upgrade with real encrypted migration fixtures, rollback behavior, and
   private-CA connectivity on representative devices. Upgrade continuity is proved
   by `tool/verify_upgrade_continuity.sh` plus the manual product-state tier in
   [release-signing.md](release-signing.md); a successful build is never
   sufficient evidence on its own.
7. Publish APK, hash, version notes, and minimum protocol compatibility through the
   self-hosted/local distribution channel.
8. For the Private Experimental deployment, deliver the ADR-044 written disclosure with
   the artifact. This is release-blocking, not a courtesy. It must state, in writing:
   that no part of the cryptography has been independently reviewed; that messages
   arrive only while the app is running, because there is no background delivery and no
   notifications; that group messaging is experimental and its history can be lost on an
   update; that history exists only on the device and uninstalling destroys it
   permanently; that a recovery secret plus a second enrolled device recovers identity
   but never history; and that the build is for evaluation among people who already
   trust each other, and is not appropriate for anyone whose safety depends on the
   confidentiality of their messages.

   The same seven facts are also stated inside the application, as the deployment
   disclosure inside the mandatory enrollment security notice ([ADR-045](decisions.md)).
   The written delivery is not replaced by it and stays release-blocking: it reaches a
   recipient before they install, and it is the only copy a person who declines to
   install ever sees.

9. If `DeploymentDisclosure.revision` in
   `lib/app/config/deployment_disclosure.dart` differs from the revision carried by the
   previously distributed artifact, re-deliver the written disclosure to **every**
   existing recipient, not only to new ones. The revision moves when and only when what
   the build promises moves, so a changed revision is exactly the case where a person
   who already enrolled has been told something that is no longer true. Their install
   will not re-show the notice; that is the deliberate rejection of periodic
   re-acknowledgement recorded in ADR-045, and this step is what pays for it.

Updates are explicit user/admin actions. The app may check only the self-hosted signed
metadata endpoint. It never fetches executable code or dependencies dynamically.

## Post-v1 Web release

Web is not shipped in version 1. The following is a future release procedure and is not
part of the Android release gate:

1. Build and test the Flutter web bundle, shared crypto Wasm, and LiveKit E2EE worker from
   the same reviewed tag.
2. Generate a content-hash manifest/SRI metadata for every static artifact.
3. Verify the strict CSP and security headers against the exact compiled output.
4. Serve immutable hashed assets and a no-store/revalidated root document from the
   self-hosted origin; no service worker may pin an incompatible protocol bundle forever.
5. Run browser compatibility, storage migration, multi-tab, WebSocket origin, and voice
   E2EE tests against the deployed staging artifact.
6. Publish the production artifact hash through an independent operator channel where
   users can verify it.

Recommended response posture includes HSTS, `nosniff`, strict referrer/permissions
policies, restrictive CSP, frame denial, correct Wasm MIME, and cache rules. Exact header
values belong in version-controlled server configuration and automated deployment tests.

## Rollout order

Protocol changes use expand/migrate/contract:

1. Backend changes remain compatible with the currently released client.
2. Release a client that can read old/new but writes old.
3. Confirm adoption and migration health without collecting sensitive telemetry.
4. Enable new writes through local/operator-controlled capability configuration.
5. Remove old reads only in a later major release after the retention window.

Because the app has no remote third-party feature flag service, flags are signed
self-hosted configuration or compile-time decisions and cannot weaken cryptography.

## Rollback

- A future Web rollback is permitted only if the older bundle can read the migrated local
  DB and crypto formats.
- Android downgrades are not assumed safe. Roll forward with a fixed build unless a tested
  compatibility path exists.
- Never restore old ratchet/MLS state over newer state.
- Preserve encrypted user data during application/schema failures; do not "repair" by
  deletion without explicit informed user action.
- Backend rollback must preserve API behavior required by deployed clients and avoid
  resurrecting acked/revoked state.

## Operations without international internet

Before every production release, isolate the environment from foreign networks and prove:

- build succeeds from approved mirrors/caches;
- version-1 application assets, fonts, CA material, APIs, Redis/PostgreSQL, nginx,
  LiveKit, and TURN are local/self-hosted;
- Android installation/update works. Web loading is post-v1.
- two-phase enrollment, cross-signing/SAS, PQXDH and the production-approved PQ MLS
  profile, device-log gossip,
  register/login/message/attachment/voice/identity-recovery flows work;
- seven-day queue gaps trigger fresh-Welcome recovery and history transfers succeed only
  device-to-device with no server-history dependency;
- DNS and connectivity checks do not contact foreign services.

## Incident response

Maintain runbooks for compromised signing key, compromised TLS/JWT/backend host, leaked
web bundle, vulnerable dependency, protocol flaw, corrupted migration, and lost update
channel. A protocol/crypto incident may require device/session invalidation and a new
major version; availability pressure never authorizes silent plaintext or encryption
downgrade.

## Production release checklist

- [ ] Final application name, icon, Android ID, and production origin approved.
- [ ] Documentation and ADR register match implementation.
- [ ] Security review findings closed or explicitly release-blocking.
- [ ] Crypto/interoperability vectors pass on Android. Supported-browser vectors are
  post-v1.
- [ ] Database and crypto-state migrations pass from all supported Android versions.
- [ ] Backend contract and multi-device E2E suites pass.
- [ ] Accessibility, RTL, performance, battery, and voice gates pass.
- [ ] No forbidden network calls or sensitive logs/artifacts detected.
- [ ] SBOM, hashes, signatures, update metadata, and rollback plan archived.
- [ ] Staging rehearsal and isolated-network production rehearsal completed.
