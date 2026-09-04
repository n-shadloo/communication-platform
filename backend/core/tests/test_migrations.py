"""The migration history: one file for each app, and a replay in both directions.

ADR-0009 regenerated the history, which is available exactly once — before the
first real user — and the precondition is that the deployment recreates the
database rather than migrating it. What that buys has to be proved rather than
assumed, so this file replays the whole history onto an empty database of its
own and then unapplies every app to zero.

The replay never touches the test database. `migrate <app> zero` drops tables,
and a failure part-way through would leave the rest of the suite without a
schema.
"""

import copy

import pytest
from django.apps import apps
from django.conf import settings
from django.core.management import call_command
from django.db import connections
from django.db.migrations.loader import MigrationLoader
from django.db.utils import load_backend

INITIAL = "0001_initial"
ALIAS = "migration_replay"

# The apps of this project that own a table. `core` and `realtime` declare no
# model, so they carry no migrations directory at all.
PROJECT_APPS = sorted(
    config.label
    for config in apps.get_app_configs()
    # `get_models()` returns a generator, which is truthy however empty it is.
    if not config.name.startswith("django.") and any(config.get_models())
)

# What each `0001_initial` depends on inside this project. `accounts` holds
# `AUTH_USER_MODEL`, so every app with a foreign key to a user waits for it;
# `messaging` queues to a device, so it waits for `devices`. `voicerooms` holds
# no foreign key at all — a room is a capability id and an encrypted name.
DEPENDENCIES = {
    "accounts": set(),
    "attachments": {"accounts"},
    "devices": {"accounts"},
    "messaging": {"devices"},
    "vault": {"accounts"},
    "voicerooms": set(),
}


def teardown_order():
    """The apps in reverse dependency order.

    Each `zero` then unapplies its own app and nothing else. Alphabetical order
    would take `accounts` first, which cascades through every app that depends on
    it and leaves the rest of the loop unapplying nothing.
    """
    remaining, order = dict(DEPENDENCIES), []
    while remaining:
        free = sorted(app for app, needs in remaining.items() if not needs)
        assert free, f"a cycle between {sorted(remaining)}"
        order.extend(free)
        remaining = {
            app: needs - set(free) for app, needs in remaining.items() if app not in free
        }
    return list(reversed(order))


def project_tables():
    return {model._meta.db_table for model in apps.get_models() if _is_ours(model)}


def _is_ours(model):
    return model._meta.app_label in PROJECT_APPS


def tables_in(alias):
    with connections[alias].cursor() as cursor:
        cursor.execute(
            "SELECT tablename FROM pg_tables WHERE schemaname = current_schema()"
        )
        return {row[0] for row in cursor.fetchall()}


@pytest.fixture
def empty_database():
    """An empty database of its own, created and dropped around the test.

    Registered on the connection handler and never in `settings.DATABASES`: an
    alias the settings name is one Django's own test guard forbids a connection
    to unless the test declares it, and this alias does not exist when the guard
    is installed. A connection the handler holds and the settings do not is the
    dynamically created case the guard admits.

    The connection carries no pool. The replay is one session running DDL, and a
    pool's idle connection would still hold the database open when the drop runs.
    """
    name = f"{connections['default'].settings_dict['NAME']}_{ALIAS}"
    # `CREATE DATABASE` and `DROP DATABASE` take no bound parameter, so the name is
    # interpolated into the statement. It is the configured database name plus a
    # constant, never a request value, and this is what keeps it that way: anything
    # but a plain identifier never reaches the statement.
    assert name.replace("_", "").isalnum(), name
    quoted = connections["default"].ops.quote_name(name)
    settings_dict = copy.deepcopy(connections["default"].settings_dict)
    settings_dict["NAME"] = name
    settings_dict["OPTIONS"] = {
        key: value for key, value in settings_dict["OPTIONS"].items() if key != "pool"
    }
    with connections["default"].cursor() as cursor:
        cursor.execute(f"DROP DATABASE IF EXISTS {quoted}")
        cursor.execute(f"CREATE DATABASE {quoted}")
    backend = load_backend(settings_dict["ENGINE"])
    connections[ALIAS] = backend.DatabaseWrapper(settings_dict, alias=ALIAS)
    try:
        yield ALIAS
    finally:
        connections[ALIAS].close()
        del connections[ALIAS]
        with connections["default"].cursor() as cursor:
            cursor.execute(f"DROP DATABASE IF EXISTS {quoted}")


def test_every_app_owns_exactly_one_migration():
    """ADR-0009: one regenerated `0001_initial` for each app, and nothing before
    it. A second file here means the history started growing again, which is
    correct from phase 3 on and a defect inside this run."""
    loader = MigrationLoader(None, ignore_no_migrations=True)
    ours = {(app, name) for app, name in loader.disk_migrations if app in PROJECT_APPS}

    assert ours == {(app, INITIAL) for app in PROJECT_APPS}


def test_each_initial_declares_the_dependencies_recorded_here():
    """The order the apps migrate in. A dependency that disappears is a migration
    that can run before the table it points at exists."""
    loader = MigrationLoader(None, ignore_no_migrations=True)
    declared = {
        app: {
            dependency
            for dependency, _name in loader.disk_migrations[(app, INITIAL)].dependencies
            if dependency in PROJECT_APPS and dependency != app
        }
        for app in PROJECT_APPS
    }

    assert declared == DEPENDENCIES


def test_the_graph_has_one_leaf_for_each_app():
    """Two leaves in one app is the conflicting-history state `migrate` refuses to
    run, and it reaches the tree as a merge nobody asked for."""
    loader = MigrationLoader(None, ignore_no_migrations=True)
    leaves = {node for node in loader.graph.leaf_nodes() if node[0] in PROJECT_APPS}

    assert leaves == {(app, INITIAL) for app in PROJECT_APPS}


def test_no_migration_names_a_model_or_an_app_that_left():
    """Invariant: no migration file references a removed model or a removed app.
    `KeyPackage` and the MLS group state went in phase 1, and no token table has
    ever existed — `simplejwt`'s blacklist is a per-device login record at rest,
    which is what ADR-0006 refuses to hold."""
    gone = ("KeyPackage", "keypackage", "token_blacklist", "HistoryRecord")
    written = {
        app: (settings.BASE_DIR / app / "migrations" / f"{INITIAL}.py").read_text()
        for app in PROJECT_APPS
    }
    found = {
        (app, marker)
        for app, source in written.items()
        for marker in gone
        if marker in source
    }

    assert found == set()


@pytest.mark.django_db(transaction=True)
def test_the_history_applies_to_an_empty_database(empty_database):
    """What a deployment of this version does: create the database, migrate once.
    ADR-0009 makes that the only supported path, so it is the one this proves."""
    call_command("migrate", database=empty_database, verbosity=0)

    assert project_tables() <= tables_in(empty_database)


@pytest.mark.django_db(transaction=True)
@pytest.mark.parametrize("app", teardown_order())
def test_every_app_unapplies_to_zero(empty_database, app):
    """Reversibility of the whole history, app by app. Every operation in it is a
    `CreateModel`, so the reverse is a `DROP TABLE` and nothing has to be
    recovered — but an app that cannot reach zero is one whose `0001_initial`
    carries an operation that lies about its own reverse."""
    call_command("migrate", database=empty_database, verbosity=0)

    call_command("migrate", app, "zero", database=empty_database, verbosity=0)

    assert (
        tables_in(empty_database)
        & {
            model._meta.db_table
            for model in apps.get_models()
            if model._meta.app_label == app
        }
        == set()
    )


@pytest.mark.django_db(transaction=True)
def test_the_whole_history_unapplies_in_reverse_dependency_order(empty_database):
    """Every app to zero, one call each, leaving no table of this project behind."""
    call_command("migrate", database=empty_database, verbosity=0)

    for app in teardown_order():
        call_command("migrate", app, "zero", database=empty_database, verbosity=0)

    assert tables_in(empty_database) & project_tables() == set()
