import pytest
from django.contrib.admin.sites import AdminSite

from accounts.admin import UserAdmin
from accounts.models import User

pytestmark = pytest.mark.django_db


@pytest.fixture
def user_admin():
    return UserAdmin(User, AdminSite())


def test_activation_is_an_explicit_owner_action(user_admin):
    assert "activate_accounts" in user_admin.actions
    assert "deactivate_accounts" in user_admin.actions


def test_activate_action_flips_is_active(user_admin, rf):
    user = User.objects.create_user(username="bob", password="a-long-enough-pw")
    assert user.is_active is False

    user_admin.activate_accounts(rf.post("/"), User.objects.filter(pk=user.pk))

    user.refresh_from_db()
    assert user.is_active is True


def test_deactivate_action_flips_is_active_back(user_admin, rf):
    user = User.objects.create_user(username="bob", password="a-long-enough-pw",
                                    is_active=True)

    user_admin.deactivate_accounts(rf.post("/"), User.objects.filter(pk=user.pk))

    user.refresh_from_db()
    assert user.is_active is False


def test_action_only_touches_the_selected_accounts(user_admin, rf):
    selected = User.objects.create_user(username="bob", password="a-long-enough-pw")
    untouched = User.objects.create_user(username="carol", password="a-long-enough-pw")

    user_admin.activate_accounts(rf.post("/"), User.objects.filter(pk=selected.pk))

    selected.refresh_from_db()
    untouched.refresh_from_db()
    assert selected.is_active is True
    assert untouched.is_active is False
