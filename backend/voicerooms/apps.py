from django.apps import AppConfig


class VoiceroomsConfig(AppConfig):
    """A migrations package and nothing else.

    ADR-0021 removed the room object, and `0002_delete_room` is what carries that
    removal to a database that already holds the table. The app stays installed
    until every environment has applied it, and declares no `verbose_name`
    because it registers no model and reaches no page of the panel.
    """

    name = "voicerooms"
