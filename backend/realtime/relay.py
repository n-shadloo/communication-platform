"""The relay credential: one coturn TURN REST API username and password.

A client needs an ICE server to place a call, and the only one this deployment
has is the self-hosted coturn of ADR-0021. Under `use-auth-secret` coturn keeps
no per-user account state at all: a username is an expiry timestamp, a colon and
any string, and the password is an HMAC over that username under a secret the
two processes share. So this module *mints* a credential rather than storing
one. There is no row, no table and no migration behind it, and nothing to revoke
— a credential dies of its own expiry.

The username is the whole of what the credential tells coturn about a caller,
and it travels in the clear on a control channel that carries no TLS. This one
carries an expiry and sixteen random bytes: no account id, no device id, and
nothing derived from either. Two credentials of one device therefore look
exactly like credentials of two devices, and nothing in a credential joins to
anything the backend holds. What the relay learns beyond that — the source
address of each allocation, the peer pairs, the sizes and the timing — it
learns from the traffic, and `SECURITY.md` states it.
"""

import base64
import hashlib
import hmac
import secrets
import time

from django.conf import settings

# The bytes of randomness a username carries. Sixteen is the width of every other
# unguessable value this system mints, and it is what keeps two credentials of one
# account unlinkable to the relay that checks them.
USERNAME_RANDOM_BYTES = 16


def mint(now=None):
    """The credential a caller gets: the URLs, the username, the password, and
    the seconds the pair is good for.

    `now` is a seam the tests use to fix the expiry the username carries; no
    caller in the application passes it.
    """
    lifetime = settings.RELAY_CREDENTIAL_TTL_SECONDS
    issued = int(time.time() if now is None else now)
    nonce = base64.urlsafe_b64encode(secrets.token_bytes(USERNAME_RANDOM_BYTES))
    username = f"{issued + lifetime}:{nonce.decode()}"
    return {
        "urls": list(settings.TURN_URLS),
        "username": username,
        "credential": credential_for(username),
        "expires_in": lifetime,
    }


def credential_for(username):
    """The TURN REST API password: standard base64 of HMAC-SHA1 over the username
    under the shared secret.

    SHA-1 is not a choice this project makes. It is the digest coturn computes
    and compares, so a credential under any other digest is one the relay
    refuses. What stands on it is an HMAC — a construction whose security rests
    on the key rather than on the collision resistance SHA-1 has lost — over a
    username that expires within the lifetime below.
    """
    digest = hmac.new(
        settings.TURN_STATIC_AUTH_SECRET.encode(),
        username.encode(),
        hashlib.sha1,
    ).digest()
    return base64.b64encode(digest).decode()
