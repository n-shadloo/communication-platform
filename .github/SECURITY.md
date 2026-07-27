# Security Policy

## Reporting a vulnerability

Report privately through this repository's [GitHub private security
advisories](https://github.com/n-shadloo/communication-platform/security/advisories/new).
Do not file a vulnerability as a public issue or a public pull request.

Include what an attacker gains, the steps to reproduce it, and the commit you observed it
on. If you are unsure whether something qualifies, report it privately anyway.

## What to expect

This is a small personal project with two maintainers, one per side of the split in
[CONTRIBUTING.md](CONTRIBUTING.md): server and protocol issues reach
[Nima Shadloo](https://github.com/n-shadloo), client-side cryptography reaches
[realSeyed](https://github.com/realSeyed). There is no service-level agreement and no
bounty. Expect a best-effort acknowledgement and a fix on the timescale of spare time. A
follow-up comment on the same advisory is welcome if you hear nothing.

## Supported versions

`main` only. There are no releases, tags, or backports.

## In scope

- Anything that lets the server read message, attachment, group, or voice content.
- Anything that lets the server learn group membership beyond the routing observation
  already documented as a limitation.
- Anything that lets the server or a third party impersonate a device or a user.
- Flaws in the cryptographic protocol or in the client-server contract that upholds it.
- Authentication or authorization bypass, including device-scoped token handling.

## Out of scope

Metadata exposure that is already documented as a known and accepted limitation —
notably that an adversary with live root on the server can observe who talks to whom and
when.

Read [backend/SECURITY.md](../backend/SECURITY.md) before reporting. That document states
what the system protects and enumerates the residual risk it does not, so you can tell an
acknowledged limitation from a real finding. This file covers only how to report a case
where the system fails to keep a property it claims.
