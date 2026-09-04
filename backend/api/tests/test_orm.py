"""The one bracket between an async route and the Django ORM.

`api/orm.py` is four lines and each one is load-bearing: the unit runs on the
thread that owns the connection, the bracket that releases that connection runs
on the same thread, and the `finally` runs whatever the unit raised. Driven
directly rather than through a route, because a route proves only that the whole
stack answered.

What a released connection looks like here is `connection.connection is None` on
the wrapper, not a closed socket: the deployment runs psycopg's pool, so
`close_old_connections` hands the connection back to the pool and the pool hands
the same object out again on the next `ensure_connection`.
"""

import threading

import pytest
from asgiref.sync import ThreadSensitiveContext
from django.db import connection

from accounts.models import User
from api.orm import run_unit

# transaction=True because the bracket releases the connection around every unit
# of work, which under a wrapping test transaction would sever the one the test
# itself holds.
pytestmark = pytest.mark.django_db(transaction=True)


def add(left, right=0):
    return left + right


def boom():
    raise ValueError("the unit failed")


def held_on_entry_then_open():
    """Whether this thread was still holding a connection when the unit began."""
    held = connection.connection is not None
    connection.ensure_connection()
    return held


async def test_the_value_the_unit_returns_is_what_the_awaiter_receives():
    assert await run_unit(add, 2, right=3) == 5


async def test_a_keyword_named_fn_reaches_the_unit_rather_than_the_bracket():
    """`fn` is positional-only, so a unit whose own signature takes a `fn` keyword
    stays callable. Without the `/` this is a `TypeError` about two values."""

    def echo(**kwargs):
        return kwargs

    assert await run_unit(echo, fn=1) == {"fn": 1}


async def test_the_unit_reads_the_database_from_the_orm_thread(active_user):
    """The normal path: a query inside the unit sees the rows the test committed."""
    names = await run_unit(lambda: list(User.objects.values_list("username", flat=True)))

    assert names == [active_user.username]


async def test_an_exception_inside_the_unit_reaches_the_awaiter():
    with pytest.raises(ValueError, match="the unit failed"):
        await run_unit(boom)


async def test_a_unit_never_inherits_the_connection_the_last_one_opened():
    """`CONN_MAX_AGE` is 0, so every connection is obsolete the moment it is
    opened, and this bracket is the only thing that releases it: Django fires
    `close_old_connections` from the request signals this process never sends."""
    first = await run_unit(held_on_entry_then_open)
    second = await run_unit(held_on_entry_then_open)

    assert first is False
    assert second is False


async def test_the_connection_is_released_even_when_the_unit_raises():
    """The bracket is a `finally`. Without it a failing unit leaks the connection
    it opened, and a route that fails often runs the pool dry."""

    def fail_with_a_live_connection():
        connection.ensure_connection()
        raise ValueError("the unit failed")

    with pytest.raises(ValueError):
        await run_unit(fail_with_a_live_connection)

    assert (await run_unit(held_on_entry_then_open)) is False


async def test_two_units_of_one_context_run_on_one_thread():
    """What makes a transaction opened inside a unit predictable: the second unit
    of a request lands on the thread that holds the first one's connection."""
    async with ThreadSensitiveContext():
        first = await run_unit(threading.get_ident)
        second = await run_unit(threading.get_ident)

    assert first == second
