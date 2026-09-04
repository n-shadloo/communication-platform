"""Write the OpenAPI document of this API, or fail when the committed one drifted.

The document is generated from the composed application, so it is a projection of
the routes and the models rather than a second description of them. The committed
artefact is what a client generates from, and `--check` is what keeps the two the
same. ADR-0008 records why the command lives on the Django side even though
FastAPI produces the document: `manage.py` is the one entry point that has already
run `django.setup()`.
"""

import json

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

ARTEFACT = "openapi.json"


def rendered():
    """The document as it is written to disk.

    Sorted keys and a trailing newline, so the bytes are a function of the routes
    and the models alone. Without the sort a dictionary order would move the file
    on a run that changed nothing, and every drift check after it would be noise.
    """
    # Imported inside the function: the module builds the whole ASGI application,
    # and nothing but this command needs it built.
    from config.asgi import api_application

    return json.dumps(api_application.openapi(), indent=2, sort_keys=True) + "\n"


class Command(BaseCommand):
    help = "Write backend/openapi.json, or with --check fail when it has drifted."

    def add_arguments(self, parser):
        parser.add_argument(
            "--check",
            action="store_true",
            help=(
                "Write nothing. Exit non-zero when the file on disk differs from "
                "the document this code generates."
            ),
        )

    def handle(self, *args, **options):
        path = settings.BASE_DIR / ARTEFACT
        document = rendered()
        if not options["check"]:
            path.write_text(document, encoding="utf-8")
            self.stdout.write(f"wrote {ARTEFACT}")
            return
        on_disk = path.read_text(encoding="utf-8") if path.exists() else None
        if on_disk != document:
            # The difference itself is not printed: the reader regenerates and
            # reads the diff in their own tree, and a schema dumped into a CI log
            # is a route map in a place nobody controls.
            raise CommandError(
                f"{ARTEFACT} is not the document this code generates. "
                "Run `python manage.py openapi` and commit the result."
            )
        self.stdout.write(f"{ARTEFACT} matches the generated document")
