"""The one bracket between an async route and the Django ORM."""

from asgiref.sync import sync_to_async
from django.db import close_old_connections


def _bracketed(fn, args, kwargs):
    close_old_connections()
    try:
        return fn(*args, **kwargs)
    finally:
        close_old_connections()


async def run_unit(fn, /, *args, **kwargs):
    """Run one synchronous unit of work on the ORM thread.

    The bracket runs on the thread that runs the query, which is the only place
    it works: Django holds each connection thread-locally and fires
    `close_old_connections` from the request signals that this process never
    sends. `thread_sensitive=True` keeps every unit of one request on one
    thread, which is what makes a transaction opened inside `fn` predictable.

    `fn` never awaits. No released Django has an async transaction, and a lazy
    relation load in async context raises `SynchronousOnlyOperation`.
    """
    return await sync_to_async(_bracketed, thread_sensitive=True)(fn, args, kwargs)
