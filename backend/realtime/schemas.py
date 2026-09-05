"""The outbound model of the relay route.

There is no inbound model: the route takes no body. The caller is the token it
presents, and everything the answer carries is computed rather than read.
"""

from pydantic import BaseModel


class RelayCredentialOut(BaseModel):
    """One ephemeral coturn credential.

    `urls` is the configured `turn:` list, in the order the operator wrote it.
    `username` is the Unix expiry timestamp, a colon and sixteen random bytes as
    URL-safe base64. `credential` is standard base64 of HMAC-SHA1 over that
    username. `expires_in` is the seconds the pair stays good for, counted from
    the moment it was minted.
    """

    urls: list[str]
    username: str
    credential: str
    expires_in: int
