"""The audit log, and what the panel takes off the site.

`django.contrib.auth` registers `Group` on import. This project has one role — the
superuser owner — so a group would be a permission surface nobody administers and
every reader has to reason about. It leaves (ADR-0011).
"""

from django.contrib import admin
from django.contrib.admin.models import ADDITION, CHANGE, DELETION, LogEntry
from django.contrib.auth.models import Group
from django.utils.translation import gettext_lazy as _
from unfold.decorators import display

from core.panel import PanelModelAdmin

admin.site.unregister(Group)

# The first item of each pair is the key `@display(label=...)` colours the badge
# by; the second is what the operator reads.
_ACTIONS = {
    ADDITION: ("added", _("Added")),
    CHANGE: ("changed", _("Changed")),
    DELETION: ("deleted", _("Deleted")),
}


@admin.register(LogEntry)
class AuditAdmin(PanelModelAdmin):
    """Every administrative act, and nothing else.

    Read-only on all three writes, because an audit trail the operator can edit is
    not one; `PanelModelAdmin` already denies them.

    The columns are the security decision here. `object_id` is deliberately absent
    from `list_display`, `fields` and `search_fields`: for a deleted attachment it
    holds that attachment's capability id, and the log outlives the row.
    """

    list_display = ("action_time", "actor", "action", "touched", "summary")
    list_display_links = None
    fields = ("action_time", "actor", "touched", "summary")
    readonly_fields = fields
    list_filter = ("action_flag", "action_time", "user")
    search_fields = ("user__username", "object_repr")
    ordering = ("-action_time",)
    date_hierarchy = "action_time"
    # The two joins the columns would otherwise make once for each row.
    list_select_related = ("user", "content_type")

    @display(description=_("Operator"), ordering="user__username")
    def actor(self, obj):
        return obj.user.get_username()

    @display(
        description=_("Action"),
        ordering="action_flag",
        label={"added": "success", "changed": "info", "deleted": "danger"},
    )
    def action(self, obj):
        return _ACTIONS.get(obj.action_flag, ("changed", _("Unknown")))

    @display(description=_("What was touched"), ordering="object_repr")
    def touched(self, obj):
        """`object_repr` under a name the operator reads. The panel writes every one
        of these itself (`PanelModelAdmin.log_deletions` and `core.panel.audit`), so
        it is a plain-language description and never `str(obj)`."""
        return obj.object_repr

    @display(description=_("What happened"))
    def summary(self, obj):
        return obj.get_change_message()
