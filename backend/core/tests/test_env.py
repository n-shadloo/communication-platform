"""The four environment accessors every settings module is built out of.

`config/settings/base.py` reads nothing from `os.environ` directly: it reads it
through these, so a missing required variable is one exception with the variable's
name in it rather than a `KeyError` from whichever line happened to run first.
Each accessor has a default path, a present-value path and a boundary — the empty
string, which an operator's `.env` produces for every key they left blank.
"""

import pytest

from core.env import ImproperlyConfigured, env, env_bool, env_int, env_list

KEY = "CHATAPP_TEST_ONLY_VARIABLE"


@pytest.fixture(autouse=True)
def _unset(monkeypatch):
    """Every test starts with the variable absent, whatever the shell holds."""
    monkeypatch.delenv(KEY, raising=False)


class TestEnv:
    def test_a_present_variable_is_returned_verbatim(self, monkeypatch):
        monkeypatch.setenv(KEY, "  spaced value  ")

        assert env(KEY) == "  spaced value  "

    def test_an_absent_variable_falls_back_to_the_default(self):
        assert env(KEY, default="fallback") == "fallback"

    def test_an_absent_variable_with_no_default_names_itself_in_the_error(self):
        """The failure an operator sees on a half-filled `.env`. Without the name
        it is a stack trace in whichever settings line read it first."""
        with pytest.raises(ImproperlyConfigured) as raised:
            env(KEY)

        assert KEY in str(raised.value)

    def test_an_explicit_none_default_is_a_value_and_not_a_missing_variable(self):
        """The sentinel is a private object, not `None`, so a setting whose absence
        is meaningful can say so."""
        assert env(KEY, default=None) is None

    def test_the_empty_string_is_a_value_and_not_a_missing_variable(self, monkeypatch):
        """A key an operator left blank is set, and `LIVEKIT_URL=` is how voice is
        turned off — reading it as absent would substitute the default instead."""
        monkeypatch.setenv(KEY, "")

        assert env(KEY, default="fallback") == ""


class TestEnvBool:
    @pytest.mark.parametrize("raw", ["1", "true", "TRUE", "Yes", " on ", "True"])
    def test_every_affirmative_spelling_reads_true(self, monkeypatch, raw):
        monkeypatch.setenv(KEY, raw)

        assert env_bool(KEY) is True

    @pytest.mark.parametrize("raw", ["0", "false", "no", "off", "", "  ", "maybe"])
    def test_anything_else_reads_false(self, monkeypatch, raw):
        """Not a parse failure: an unrecognised value is off, so a typo never turns
        a hardening flag on."""
        monkeypatch.setenv(KEY, raw)

        assert env_bool(KEY) is False

    def test_an_absent_variable_takes_the_default(self):
        assert env_bool(KEY) is False
        assert env_bool(KEY, default=True) is True

    def test_a_present_variable_overrides_a_true_default(self, monkeypatch):
        monkeypatch.setenv(KEY, "no")

        assert env_bool(KEY, default=True) is False


class TestEnvInt:
    def test_a_present_number_is_parsed(self, monkeypatch):
        monkeypatch.setenv(KEY, "42")

        assert env_int(KEY, default=7) == 42

    def test_a_negative_number_is_parsed(self, monkeypatch):
        monkeypatch.setenv(KEY, "-3")

        assert env_int(KEY, default=7) == -3

    def test_surrounding_whitespace_is_tolerated(self, monkeypatch):
        monkeypatch.setenv(KEY, " 7 ")

        assert env_int(KEY, default=0) == 7

    def test_an_absent_variable_takes_the_default(self):
        assert env_int(KEY, default=15) == 15
        assert env_int(KEY) is None

    def test_a_blank_variable_takes_the_default(self, monkeypatch):
        """The boundary: `DB_POOL_MAX_SIZE=` in an operator's file is a key that is
        set and empty, and `int("")` would be a start-up crash."""
        monkeypatch.setenv(KEY, "")

        assert env_int(KEY, default=16) == 16

    def test_a_value_that_is_not_a_number_fails_loudly(self, monkeypatch):
        """The rare case, and deliberately not a silent fallback: a mistyped
        deadline must stop the process rather than run at a value nobody chose."""
        monkeypatch.setenv(KEY, "sixteen")

        with pytest.raises(ValueError):
            env_int(KEY, default=16)


class TestEnvList:
    def test_a_comma_separated_value_is_split_and_stripped(self, monkeypatch):
        monkeypatch.setenv(KEY, "a, b ,c")

        assert env_list(KEY) == ["a", "b", "c"]

    def test_empty_items_are_dropped(self, monkeypatch):
        """`DJANGO_ALLOWED_HOSTS=a,,b,` — a trailing comma must not produce an
        empty allowed host, which would match a request with no `Host` at all."""
        monkeypatch.setenv(KEY, "a,,b, ,")

        assert env_list(KEY) == ["a", "b"]

    def test_an_absent_variable_with_no_default_is_the_empty_list(self):
        assert env_list(KEY) == []

    def test_a_blank_variable_takes_the_default(self, monkeypatch):
        monkeypatch.setenv(KEY, "")

        assert env_list(KEY, default=["http://localhost"]) == ["http://localhost"]

    def test_the_default_is_copied_rather_than_shared(self):
        """The returned list is what a settings module binds. Handing back the
        default itself would let one module's `.append` change another's."""
        default = ["http://localhost"]

        returned = env_list(KEY, default=default)
        returned.append("http://evil.example")

        assert default == ["http://localhost"]
