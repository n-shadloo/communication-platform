from datetime import date, datetime

import pytest
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction

from accounts.models import ProfileBlob, User
from core.buckets import PROFILE_BUCKETS

pytestmark = pytest.mark.django_db


def test_accounts_are_inactive_until_the_owner_activates_them():
    user = User.objects.create_user(username="bob", password="a-long-enough-pw")

    assert user.is_active is False


def test_superuser_is_active_because_it_is_the_operator_account():
    operator = User.objects.create_superuser(
        username="owner", password="a-long-enough-pw"
    )

    assert operator.is_active is True
    assert operator.is_staff is True
    assert operator.is_superuser is True


@pytest.mark.parametrize(
    "supplied,stored",
    [
        ("Bob", "bob"),
        ("MIXEDcase_9", "mixedcase_9"),
        ("ALLCAPS", "allcaps"),
    ],
)
def test_username_is_normalised_to_lowercase(supplied, stored):
    user = User.objects.create_user(username=supplied, password="a-long-enough-pw")
    user.refresh_from_db()

    assert user.username == stored


def test_username_is_relowercased_on_every_save():
    user = User.objects.create_user(username="bob", password="a-long-enough-pw")

    user.username = "BOB_2"
    user.save()
    user.refresh_from_db()

    assert user.username == "bob_2"


def test_last_login_is_never_written():
    # A NULL last_login keeps login timing out of the database entirely.
    user = User.objects.create_user(username="bob", password="a-long-enough-pw")

    assert user.last_login is None


def test_password_is_stored_as_an_argon2id_hash_only():
    user = User.objects.create_user(username="bob", password="a-long-enough-pw")

    assert user.password.startswith("argon2$argon2id$")
    assert "a-long-enough-pw" not in user.password
    assert user.check_password("a-long-enough-pw") is True


def test_a_blank_username_is_refused_by_the_manager():
    """The manager is the last thing between a caller and the row: a name it
    would store as the empty string is refused before the INSERT."""
    with pytest.raises(ValueError):
        User.objects.create_user(username="", password="a-long-enough-pw")

    assert User.objects.count() == 0


def test_the_unique_index_refuses_a_case_variant_of_a_taken_name():
    """Normalisation is what makes the index case-insensitive: `BOB` is stored as
    `bob`, and the second write collides on the same value."""
    User.objects.create_user(username="bob", password="a-long-enough-pw")

    with pytest.raises(IntegrityError), transaction.atomic():
        User.objects.create_user(username="BOB", password="a-long-enough-pw")

    assert User.objects.filter(username="bob").count() == 1


@pytest.mark.parametrize("length", [3, 32])
def test_the_shortest_and_the_longest_name_pass_the_model_validator(length):
    user = User.objects.create_user(username="a" * length, password="a-long-enough-pw")

    user.full_clean(exclude=["password"])

    assert User.objects.get(pk=user.pk).username == "a" * length


@pytest.mark.parametrize("name", ["ab", "a" * 33, "has space", "Ünicode", "dash-es"])
def test_a_name_outside_the_shape_fails_the_model_validator(name):
    with pytest.raises(ValidationError) as exc_info:
        User(username=name).full_clean(exclude=["password"])

    assert "username" in exc_info.value.message_dict


def test_an_account_carries_a_date_and_never_a_time_of_day():
    """`created_date` is a DateField on purpose: a timestamp would say when a
    person joined to the minute, and `last_login` is never written at all."""
    user = User.objects.create_user(username="bob", password="a-long-enough-pw")
    user.refresh_from_db()

    assert isinstance(user.created_date, date)
    assert not isinstance(user.created_date, datetime)
    assert user.last_login is None


def test_an_account_holds_at_most_one_profile():
    user = User.objects.create_user(username="bob", password="a-long-enough-pw")
    ProfileBlob.objects.create(user=user, blob=b"\x01" * PROFILE_BUCKETS[0], version=1)

    with pytest.raises(IntegrityError), transaction.atomic():
        ProfileBlob.objects.create(
            user=user, blob=b"\x02" * PROFILE_BUCKETS[0], version=2
        )

    assert ProfileBlob.objects.count() == 1


def test_deleting_an_account_takes_its_profile_with_it():
    user = User.objects.create_user(username="bob", password="a-long-enough-pw")
    ProfileBlob.objects.create(user=user, blob=b"\x01" * PROFILE_BUCKETS[0], version=1)

    user.delete()

    assert ProfileBlob.objects.count() == 0


def test_a_profile_blob_round_trips_every_byte_value():
    """The column is opaque ciphertext: nothing about it is text, so every byte a
    client can produce has to survive the trip unchanged."""
    user = User.objects.create_user(username="bob", password="a-long-enough-pw")
    raw = bytes(range(256)) * (PROFILE_BUCKETS[0] // 256)
    ProfileBlob.objects.create(user=user, blob=raw, version=1)

    stored = ProfileBlob.objects.get(user=user)

    assert bytes(stored.blob) == raw
