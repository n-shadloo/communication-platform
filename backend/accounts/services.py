"""The synchronous units of work behind the accounts routes.

Each function opens its own transaction and never awaits. No released Django has
an async transaction, and a unit that awaited would hold its row lock while other
work ran on the same thread.
"""

import base64

from django.contrib.auth.hashers import check_password, make_password
from django.db import IntegrityError, transaction
from django.db.models import F

from accounts.models import ProfileBlob, User
from api.auth import issue_full, issue_register_scope
from api.errors import ApiError
from devices.models import Device
from realtime.bus import close_device_sockets

INVALID_CREDENTIALS = "Username or password is incorrect."

# A fixed invalid hash so an unknown-username login still spends Argon2 time.
DUMMY_HASH = make_password("timing-equalizer-not-a-real-password")


def _stale_version():
    return ApiError(409, "stale_version", "Version must increase.")


def _profile_body(profile):
    return {
        "blob": base64.b64encode(bytes(profile.blob)).decode(),
        "version": profile.version,
    }


def register(username, password):
    """Create the account in the inactive state; the owner activates it."""
    try:
        with transaction.atomic():
            user = User.objects.create_user(username=username, password=password)
    except IntegrityError:
        # The unique index is what settles two concurrent registrations on one
        # name. A prior existence probe would add a query and still race.
        raise ApiError(409, "username_taken", "That username is taken.")
    return {"user_id": str(user.id)}


def _rotate_refresh_generation(user_id, device_id):
    """Advance the device's refresh generation, and read the row at its new value.

    A login retires every refresh token the device held before it. The UPDATE is
    atomic on its own row, so two concurrent logins each read a generation that
    is current at the moment they read it, and no row lock has to span the two
    statements.
    """
    updated = Device.objects.filter(
        id=device_id, user_id=user_id, revoked_date__isnull=True
    ).update(refresh_generation=F("refresh_generation") + 1)
    if not updated:
        return None
    return (
        Device.objects.filter(id=device_id)
        .only("id", "token_generation", "refresh_generation")
        .first()
    )


def login(username, password, device_id):
    user = (
        User.objects.filter(username=username).only("id", "password", "is_active").first()
    )
    if user is None:
        check_password(password, DUMMY_HASH)  # equalize timing
        raise ApiError(401, "invalid_credentials", INVALID_CREDENTIALS)
    # user.check_password (not the bare function) carries the setter that
    # transparently re-hashes when the configured Argon2 cost changes.
    if not user.check_password(password):
        raise ApiError(401, "invalid_credentials", INVALID_CREDENTIALS)
    # Only once the password is proven does activation state become observable.
    if not user.is_active:
        raise ApiError(403, "account_inactive", "This account is awaiting activation.")

    device = _rotate_refresh_generation(user.id, device_id) if device_id else None
    if device is None:
        # No device, or one this account does not own: a short register-scope
        # token whose only power is POST /me/devices.
        return {
            "access": issue_register_scope(user),
            "user_id": str(user.id),
            "scope": "register",
        }
    access, refresh_token = issue_full(user, device)
    return {
        "access": access,
        "refresh": refresh_token,
        "user_id": str(user.id),
        "device_id": str(device.id),
        "scope": "full",
    }


def refresh(claims):
    """Rotate the pair, or detect reuse and end the whole family.

    A refresh whose `rgen` is behind the row is a replay of a token that was
    already rotated. The device row is the family: `token_generation` advances,
    every outstanding token of the device dies, and that escalation commits
    before the refusal reaches the client.

    Returns None for every refusal. A revoked device, a stale generation, a
    deactivated account and a replay are reported identically, so the client
    learns only that this token is finished.
    """
    replayed = False
    with transaction.atomic():
        device = (
            Device.objects.select_for_update()
            .select_related("user")
            .only(
                "id",
                "user_id",
                "token_generation",
                "refresh_generation",
                "user__is_active",
            )
            .filter(
                id=claims["device_id"],
                user_id=claims["user_id"],
                revoked_date__isnull=True,
            )
            .first()
        )
        if device is None or device.token_generation != claims["tgen"]:
            return None
        if not device.user.is_active:
            return None
        if device.refresh_generation != claims["rgen"]:
            device.token_generation += 1
            device.save(update_fields=["token_generation"])
            replayed = True
        else:
            device.refresh_generation += 1
            device.save(update_fields=["refresh_generation"])
            access, refresh_token = issue_full(device.user, device)
    if replayed:
        # The access tokens of the family are dead; a socket that one of them
        # opened must not outlive them.
        close_device_sockets(claims["device_id"])
        return None
    return {"access": access, "refresh": refresh_token}


def logout(user_id, device_id):
    """End the session: every token of the device dies and its sockets drop."""
    Device.objects.filter(id=device_id, user_id=user_id).update(
        token_generation=F("token_generation") + 1
    )
    close_device_sockets(device_id)


def directory():
    """Every activated account, ordered by username. This is a small private
    server and the directory is how clients pick conversation partners."""
    return {
        "users": [
            {"user_id": str(row["id"]), "username": row["username"]}
            for row in User.objects.filter(is_active=True)
            .order_by("username")
            .values("id", "username")
        ]
    }


def peer_profile(user_id):
    profile = (
        ProfileBlob.objects.filter(user_id=user_id, user__is_active=True)
        .only("blob", "version")
        .first()
    )
    if profile is None:
        raise ApiError(404, "not_found", "No profile for that user.")
    return _profile_body(profile)


def my_profile(user_id):
    profile = ProfileBlob.objects.filter(user_id=user_id).only("blob", "version").first()
    if profile is None:
        raise ApiError(404, "not_found", "No profile yet.")
    return _profile_body(profile)


def write_profile(user_id, raw, version):
    try:
        with transaction.atomic():
            # .only("version"): the locked read exists to compare versions, so
            # the stored blob is not dragged back with it. Branching here rather
            # than calling update_or_create avoids a second identical SELECT.
            profile = (
                ProfileBlob.objects.select_for_update()
                .filter(user_id=user_id)
                .only("version")
                .first()
            )
            if profile is None:
                ProfileBlob.objects.create(user_id=user_id, blob=raw, version=version)
            elif version <= profile.version:
                raise _stale_version()
            else:
                profile.blob = raw
                profile.version = version
                profile.save(update_fields=["blob", "version", "updated_date"])
    except IntegrityError:
        # select_for_update locks nothing when the row does not exist yet, so two
        # concurrent first writes can both clear the version check above.
        raise _stale_version()
