"""The voice-rooms page: what rooms exist, who is in them now, and deletion.

A room is an id and an encrypted name. The name never renders, so the id is how the
operator names a room — which is what a client shows its users too. Membership,
invites and media keys are client state that this server has never held; the only
live fact is the participant set, and that lives in Redis and nowhere else.
"""

from django.contrib import admin
from django.utils.translation import gettext_lazy as _
from unfold.decorators import display

from core.panel import PanelModelAdmin
from voicerooms.models import Room
from voicerooms.presence import live_counts


@admin.register(Room)
class RoomAdmin(PanelModelAdmin):
    """Read-only, plus Django's own delete."""

    list_display = ("id", "live_now", "created_date", "updated_date")
    list_display_links = ("id",)
    list_filter = ("created_date", "updated_date")
    ordering = ("-created_date",)
    date_hierarchy = "created_date"
    fields = ("id", "created_date", "updated_date")
    readonly_fields = fields

    def has_delete_permission(self, request, obj=None):
        """Deletion is the one destructive act here, and Django's own
        `delete_selected` gates it: an intermediate page states the scope before it
        runs, and `PanelModelAdmin.log_deletions` writes one audit row for each
        room."""
        return self.has_view_permission(request, obj)

    def panel_repr(self, obj):
        return f"room {obj.pk}"

    def get_changelist_instance(self, request):
        """Read the live counts for the page in one round trip.

        The count is a Redis set cardinality, so a column callable would be one
        command for each row. `ChangeList.__init__` has already run its own query by
        the time this returns, so `result_list` is the page and nothing wider.
        """
        changelist = super().get_changelist_instance(request)
        self._live = live_counts([room.pk for room in changelist.result_list])
        return changelist

    @display(description=_("In the room now"))
    def live_now(self, obj):
        return getattr(self, "_live", {}).get(str(obj.pk), 0)
