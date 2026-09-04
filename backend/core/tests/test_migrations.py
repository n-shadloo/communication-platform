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
import re
from io import StringIO

import pytest
from django.apps import apps
from django.conf import settings
from django.core.management import call_command
from django.db import connections, transaction
from django.db.migrations.loader import MigrationLoader
from django.db.migrations.recorder import MigrationRecorder
from django.db.utils import load_backend

INITIAL = "0001_initial"
ALIAS = "migration_replay"

# Every migration this project owns, in the order each app applies them. A file
# that is not written here fails `test_every_app_owns_the_migrations_recorded_here`,
# which is what forces a new migration through the classification below rather than
# into the tree unreviewed.
HISTORY = {
    "accounts": [INITIAL],
    "attachments": [INITIAL],
    "devices": [INITIAL],
    "messaging": [INITIAL, "0002_index_the_retention_filter"],
    "vault": [INITIAL],
    "voicerooms": [INITIAL],
}

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


def test_every_app_owns_the_migrations_recorded_here():
    """ADR-0009 regenerated the history, so each app starts at one `0001_initial`
    and nothing precedes it. What follows grows, and `HISTORY` is the record of
    what it grew to: a file nobody wrote down fails here, which is what puts every
    new migration through the classification below."""
    loader = MigrationLoader(None, ignore_no_migrations=True)
    ours = {(app, name) for app, name in loader.disk_migrations if app in PROJECT_APPS}

    assert ours == {(app, name) for app, names in HISTORY.items() for name in names}
    assert set(HISTORY) == set(PROJECT_APPS)


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

    assert leaves == {(app, names[-1]) for app, names in HISTORY.items()}


def test_no_migration_names_a_model_or_an_app_that_left():
    """Invariant: no migration file references a removed model or a removed app.
    `KeyPackage` and the MLS group state went in phase 1, and no token table has
    ever existed — `simplejwt`'s blacklist is a per-device login record at rest,
    which is what ADR-0006 refuses to hold."""
    gone = ("KeyPackage", "keypackage", "token_blacklist", "HistoryRecord")
    written = {
        (app, name): (settings.BASE_DIR / app / "migrations" / f"{name}.py").read_text()
        for app, names in HISTORY.items()
        for name in names
    }
    found = {
        (node, marker)
        for node, source in written.items()
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


# --- Lock classification ----------------------------------------------------------
# Every operation this project's migrations may carry, and the lock it takes on
# PostgreSQL 16. An operation outside this table is unclassified, which is what
# `test_every_operation_takes_a_classified_lock` refuses: the reviewer has to name
# the lock and decide whether it can run under traffic before the file lands.
#
# `CreateModel` takes ACCESS EXCLUSIVE, which blocks reads and writes — but only on
# a relation the same migration is creating, so no other session can name it yet.
# `AddIndexConcurrently` takes SHARE UPDATE EXCLUSIVE and blocks neither, at the
# price of two table scans and a migration that cannot be atomic.
LOCK_CLASSES = {
    "CreateModel": "ACCESS EXCLUSIVE on a relation this migration creates",
    "AddIndexConcurrently": "SHARE UPDATE EXCLUSIVE",
}

# The operations that cannot run inside a transaction block. A migration carrying
# one declares `atomic = False`, and Django raises NotSupportedError otherwise.
NON_ATOMIC_OPERATIONS = {"AddIndexConcurrently", "RemoveIndexConcurrently"}

# The statement forms the classification above admits. `sqlmigrate` output is read
# against this rather than trusted: an operation name says what Django meant, and
# the SQL says what PostgreSQL will do.
ALLOWED_STATEMENTS = (
    "CREATE TABLE",
    "CREATE INDEX CONCURRENTLY",
    "CREATE INDEX",
    "CREATE UNIQUE INDEX",
    "ALTER TABLE",  # narrowed below: ADD CONSTRAINT only
)


def migration_nodes():
    return [(app, name) for app, names in HISTORY.items() for name in names]


def loaded(app, name):
    return MigrationLoader(None, ignore_no_migrations=True).disk_migrations[(app, name)]


@pytest.mark.parametrize(("app", "name"), migration_nodes())
def test_every_operation_takes_a_classified_lock(app, name):
    """The gate on a migration nobody has priced. Every operation in the tree is one
    whose lock is written down in `LOCK_CLASSES`; an `AddField`, an `AlterField`, a
    plain `AddIndex` or an `AddConstraint` lands here as an unclassified operation
    and stays out of the tree until its lock is named and judged."""
    unclassified = {
        type(operation).__name__
        for operation in loaded(app, name).operations
        if type(operation).__name__ not in LOCK_CLASSES
    }

    assert unclassified == set(), f"{app}.{name} carries {sorted(unclassified)}"


@pytest.mark.parametrize(("app", "name"), migration_nodes())
def test_the_atomic_flag_matches_the_operations_the_migration_carries(app, name):
    """A concurrent index build outside a transaction, everything else inside one.
    Django raises NotSupportedError for the first mismatch; the second — an atomic
    migration downgraded to `atomic = False` for no reason — it accepts silently,
    and a failure part-way then leaves half the schema applied."""
    migration = loaded(app, name)
    needs_own_transaction = {
        type(operation).__name__ for operation in migration.operations
    } & NON_ATOMIC_OPERATIONS

    assert migration.atomic is not bool(needs_own_transaction)


def statements_of(sql):
    """The statements of one `sqlmigrate` run, comments and the wrapper gone."""
    body = " ".join(
        line.strip()
        for line in sql.splitlines()
        if line.strip() and not line.strip().startswith("--")
    )
    return [
        " ".join(statement.split())
        for statement in body.split(";")
        if statement.strip() and statement.strip() not in ("BEGIN", "COMMIT")
    ]


# `transaction=True`, not the default atomic wrapper: `sqlmigrate` builds the
# statements through the real schema editor, and `AddIndexConcurrently` refuses to
# do that inside a transaction — the same NotSupportedError a wrongly-atomic
# migration would raise on the deployment host.
@pytest.mark.django_db(transaction=True)
@pytest.mark.parametrize(("app", "name"), migration_nodes())
def test_the_generated_sql_is_only_the_statements_the_classification_covers(app, name):
    """The `sqlmigrate` review, run rather than remembered.

    Every statement is a relation this migration creates, or a concurrent index
    build. An `ALTER TABLE` that is anything but `ADD CONSTRAINT` on a
    same-migration table would be a rewrite or an ACCESS EXCLUSIVE hold on a
    relation with rows in it.

    The transaction wrapper is read from the same output, because the `atomic`
    flag is only a claim until the SQL carries it: a concurrent index build inside
    a `BEGIN` is a statement PostgreSQL refuses outright.
    """
    out = StringIO()
    call_command("sqlmigrate", app, name, stdout=out)
    sql = out.getvalue()
    statements = statements_of(sql)

    assert statements
    assert ("BEGIN;" in sql) is loaded(app, name).atomic
    for statement in statements:
        assert statement.startswith(ALLOWED_STATEMENTS), statement
        if statement.startswith("ALTER TABLE"):
            assert "ADD CONSTRAINT" in statement, statement


@pytest.mark.django_db(transaction=True)
def test_no_model_change_is_waiting_for_a_migration():
    """The gate that keeps the history above complete.

    A field added, renamed or altered with no migration written for it passes
    every test in this file — the recorded history still applies, still unapplies,
    and still carries the locks it was classified with — and then fails on the
    deployment host, after the code that needs the column is already serving.
    `makemigrations --check` is the question "does the disk match the models",
    and `--dry-run` is what keeps it from answering by writing the file.
    """
    out = StringIO()

    try:
        call_command("makemigrations", "--check", "--dry-run", stdout=out, verbosity=1)
    except SystemExit as exit_code:
        raise AssertionError(
            f"a model changed with no migration written for it:\n{out.getvalue()}"
        ) from exit_code


def test_the_apps_that_own_no_table_own_no_migrations_either():
    """`core` and `realtime` are plumbing: one holds the bucket sets, the opaque
    blob field and the panel's base classes, the other holds the socket gateway
    and its Redis bus. Neither declares a model, so a migrations directory under
    either is a table somebody added without deciding to."""
    tableless = sorted(
        config.label
        for config in apps.get_app_configs()
        if not config.name.startswith("django.")
        and not config.name.startswith("unfold")
        and not any(config.get_models())
    )

    assert tableless == ["core", "realtime"]
    for label in tableless:
        assert not (settings.BASE_DIR / label / "migrations").exists(), label


def test_the_recorded_history_covers_every_app_that_owns_a_table():
    """The other direction of `HISTORY`: an app that grew a model and a migration
    directory, and was never added to the record, would be replayed by nothing
    here."""
    assert sorted(HISTORY) == PROJECT_APPS


@pytest.mark.django_db(transaction=True)
@pytest.mark.parametrize("app", teardown_order())
def test_every_app_returns_to_head_after_unapplying_to_zero(empty_database, app):
    """The other half of reversibility: down is only useful if up follows it.

    A rollback on the deployment host unapplies an app and the next deploy applies
    it again, so a `0001_initial` whose reverse leaves a sequence, a constraint or
    an enum behind fails on the way back up rather than on the way down. Read from
    `django_migrations` as well as from the catalogue, because a table that exists
    while its row does not is a schema `migrate` will try to create twice.
    """
    call_command("migrate", database=empty_database, verbosity=0)
    call_command("migrate", app, "zero", database=empty_database, verbosity=0)

    call_command("migrate", app, database=empty_database, verbosity=0)

    applied = MigrationRecorder(connections[empty_database]).applied_migrations()
    assert tables_of(app) <= tables_in(empty_database)
    assert {name for recorded, name in applied if recorded == app} == set(HISTORY[app])


@pytest.mark.django_db(transaction=True)
def test_the_whole_history_returns_to_head_after_a_full_unapply(empty_database):
    """Every app to zero and the whole history applied again on top of the
    emptied database. This is the rollback a deploy of this version can perform,
    end to end, and the state it leaves is the one the next deploy migrates."""
    call_command("migrate", database=empty_database, verbosity=0)
    for app in teardown_order():
        call_command("migrate", app, "zero", database=empty_database, verbosity=0)

    call_command("migrate", database=empty_database, verbosity=0)

    applied = MigrationRecorder(connections[empty_database]).applied_migrations()
    assert project_tables() <= tables_in(empty_database)
    assert {node for node in applied if node[0] in PROJECT_APPS} == set(migration_nodes())


# --- The locks each migration actually takes ---------------------------------------
# `LOCK_CLASSES` above says what an operation is meant to take. This section runs the
# statements and reads `pg_locks`, because the operation name is a claim and the lock
# is what the deployment lives with.
#
# The eight modes, in the order the PostgreSQL documentation lists them, weakest
# first. Everything from SHARE upwards conflicts with ROW EXCLUSIVE, which is what
# every INSERT, UPDATE and DELETE holds: a migration that takes one of those on a
# populated table stops writes to it for the duration.
LOCK_STRENGTH = [
    "AccessShareLock",
    "RowShareLock",
    "RowExclusiveLock",
    "ShareUpdateExclusiveLock",
    "ShareLock",
    "ShareRowExclusiveLock",
    "ExclusiveLock",
    "AccessExclusiveLock",
]

# The tables that already exist when each migration runs, and the strongest lock it
# takes on each. A table this migration creates is absent from the map however hard
# it is locked: no other session can name a relation that does not exist yet.
#
# Every entry is SHARE ROW EXCLUSIVE and every one comes from the same statement
# shape — `ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY ... REFERENCES <other
# table>`, which locks the referenced side. It blocks writes to that table, not
# reads. ADR-0009 is what makes it free here: the deployment creates the database
# and migrates once, so nothing is populated and nothing is being written. On a
# database with rows in it, each of these would be a write outage on the named
# table for as long as the migration runs.
#
# `voicerooms` holds no foreign key at all — a room is a capability id and an
# encrypted name — so it locks nothing that exists.
BLOCKING_LOCKS = {
    ("accounts", INITIAL): {
        "auth_group": "ShareRowExclusiveLock",
        "auth_permission": "ShareRowExclusiveLock",
    },
    ("attachments", INITIAL): {"accounts_user": "ShareRowExclusiveLock"},
    ("devices", INITIAL): {"accounts_user": "ShareRowExclusiveLock"},
    ("messaging", INITIAL): {"devices_device": "ShareRowExclusiveLock"},
    ("vault", INITIAL): {"accounts_user": "ShareRowExclusiveLock"},
    ("voicerooms", INITIAL): {},
}

RELATIONS_IN_SCHEMA = """
SELECT c.relname
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = current_schema()
"""

# Relation locks this backend holds right now, catalogue relations excluded: the
# `pg_class` and `pg_namespace` reads of the query itself take locks of their own.
LOCKS_HELD = """
SELECT l.mode, c.relname, c.relkind
FROM pg_locks l
JOIN pg_class c ON c.oid = l.relation
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE l.pid = pg_backend_pid()
  AND l.locktype = 'relation'
  AND n.nspname = current_schema()
"""


def tables_of(app):
    return {
        model._meta.db_table
        for model in apps.get_models()
        if model._meta.app_label == app
    }


def atomic_nodes():
    return [node for node in migration_nodes() if loaded(*node).atomic]


def non_atomic_nodes():
    return [node for node in migration_nodes() if not loaded(*node).atomic]


def apply_the_state_before(node, alias):
    """Everything this migration depends on, and nothing of the migration itself.

    The graph is what names the parents rather than the file, because a swappable
    dependency is written as `__first__` in the source and resolved to a node only
    once the graph is built.
    """
    graph = MigrationLoader(None, ignore_no_migrations=True).graph
    for parent_app, parent_name in sorted(graph.node_map[node].parents):
        call_command("migrate", parent_app, parent_name, database=alias, verbosity=0)


def run_and_read_the_locks(alias, statements):
    """Run the statements in one transaction and read what it holds, then roll back.

    One transaction, because a lock is released at commit and this has to read it
    while it is held. The rollback is what keeps the probe from being a migration:
    nothing it created survives the call.
    """
    with connections[alias].cursor() as cursor:
        cursor.execute(RELATIONS_IN_SCHEMA)
        before = {row[0] for row in cursor.fetchall()}
    with transaction.atomic(using=alias):
        with connections[alias].cursor() as cursor:
            for statement in statements:
                cursor.execute(statement)
            cursor.execute(LOCKS_HELD)
            locks = cursor.fetchall()
            cursor.execute(RELATIONS_IN_SCHEMA)
            created = {row[0] for row in cursor.fetchall()} - before
        transaction.set_rollback(True, using=alias)
    return locks, created


def strongest(modes):
    return max(modes, key=LOCK_STRENGTH.index)


@pytest.mark.django_db(transaction=True)
@pytest.mark.parametrize(("app", "name"), atomic_nodes())
def test_each_migration_takes_only_the_locks_recorded_against_it(
    empty_database, app, name
):
    """The lock review, measured rather than argued.

    The migration's own SQL is run against a database migrated to exactly the state
    that precedes it, and `pg_locks` is read while the transaction still holds
    everything it took. Two things are asserted: no relation that already existed
    is locked harder than `BLOCKING_LOCKS` records, and nothing outside the set of
    relations this migration created is held at ACCESS EXCLUSIVE.

    What this catches in a migration somebody adds later: an `ALTER TABLE` that
    rewrites a populated table or sets a column NOT NULL without a validated
    constraint first, both of which take ACCESS EXCLUSIVE on a relation that
    already exists; a plain `CREATE INDEX` on one, which takes SHARE; and a new
    foreign key to a table that is not this migration's, which takes SHARE ROW
    EXCLUSIVE and would appear in the map the author has to write down.

    What it does not catch: how long any of them is held. A lock class is not a
    duration, and an ACCESS EXCLUSIVE on a table this migration created is free
    only because no other session can name that relation yet — the same statement
    against a populated table would be an outage. It also measures nothing about
    migrations that cannot run inside a transaction; the one this project has is
    held by the test below.
    """
    apply_the_state_before((app, name), empty_database)
    out = StringIO()
    call_command("sqlmigrate", app, name, database=empty_database, stdout=out)

    locks, created = run_and_read_the_locks(empty_database, statements_of(out.getvalue()))

    pre_existing = {
        relname: strongest([mode for mode, name_, _kind in locks if name_ == relname])
        for _mode, relname, kind in locks
        if kind == "r" and relname not in created
    }
    exclusive = {
        relname
        for mode, relname, _kind in locks
        if mode in ("AccessExclusiveLock", "ExclusiveLock")
    }

    assert created, "the migration created no relation at all"
    assert pre_existing == BLOCKING_LOCKS[(app, name)]
    assert exclusive <= created, sorted(exclusive - created)


@pytest.mark.django_db(transaction=True)
@pytest.mark.parametrize(("app", "name"), non_atomic_nodes())
def test_the_index_built_outside_a_transaction_is_built_concurrently(
    empty_database, app, name
):
    """The one migration the lock probe above cannot measure.

    `CREATE INDEX CONCURRENTLY` is refused inside a transaction block, so the
    statements cannot be run and rolled back with the lock still held. What is
    asserted instead is the statement itself: the concurrent form takes SHARE
    UPDATE EXCLUSIVE and blocks no write, where the plain form takes SHARE and
    stops every send for the length of the build. This is the largest table in the
    schema and the one every send writes to.

    The claim about which lock each form takes is PostgreSQL's documentation, not
    a measurement — an unmeasured claim, recorded as one.
    """
    apply_the_state_before((app, name), empty_database)
    out = StringIO()
    call_command("sqlmigrate", app, name, database=empty_database, stdout=out)
    statements = statements_of(out.getvalue())

    assert statements
    assert "BEGIN;" not in out.getvalue()
    for statement in statements:
        assert statement.startswith("CREATE INDEX CONCURRENTLY"), statement


# The relation a statement acts on: the table of an `ALTER TABLE`, and the table an
# index is built on rather than the index's own name.
TARGET = re.compile(
    r"^(?:ALTER TABLE"
    r'|CREATE (?:UNIQUE )?INDEX(?: CONCURRENTLY)? "[^"]+" ON)'
    r'\s+"([^"]+)"'
)


@pytest.mark.django_db(transaction=True)
@pytest.mark.parametrize(("app", "name"), migration_nodes())
def test_no_statement_alters_or_indexes_a_table_the_migration_did_not_create(app, name):
    """The rule the statement prefixes do not carry, and the one that holds for the
    migrations no transaction can wrap.

    `ALTER TABLE ... ADD CONSTRAINT` is admitted by the classification, and on a
    table the same migration creates it costs nothing. On a table that was already
    there it is a validating scan under a lock that blocks writes, and the prefix
    check would pass it. The same goes for a plain `CREATE INDEX`: on a new table
    it is free, on a populated one it takes SHARE for the whole build. The one
    statement allowed to name a table it did not create is the concurrent index
    build, which blocks nothing.
    """
    out = StringIO()
    call_command("sqlmigrate", app, name, stdout=out)
    statements = statements_of(out.getvalue())
    created = {
        statement.split('"')[1]
        for statement in statements
        if statement.startswith("CREATE TABLE")
    }

    foreign = {
        target.group(1)
        for statement in statements
        if not statement.startswith("CREATE INDEX CONCURRENTLY")
        for target in [TARGET.match(statement)]
        if target is not None and target.group(1) not in created
    }

    assert statements
    assert foreign == set()
