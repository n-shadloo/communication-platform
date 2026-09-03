import pytest

from accounts.models import User

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
