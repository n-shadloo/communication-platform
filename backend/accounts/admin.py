from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User


def _close_user_sockets(user_ids):
    """Deactivation must reach live sockets too: REST re-checks `is_active` on every
    request, but a WebSocket authenticated at connect time would otherwise keep
    relaying volatile signals until it happened to drop. Best-effort and silent,
    because the error would name device ids."""
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer
        from devices.models import Device
        layer = get_channel_layer()
        if layer is None:
            return
        device_ids = Device.objects.filter(
            user_id__in=user_ids, revoked_date__isnull=True).values_list("id", flat=True)
        for device_id in device_ids:
            async_to_sync(layer.group_send)(
                f"dev.{device_id}", {"type": "connection.close"})
    except Exception:
        pass

@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ("username",)
    list_display = ("username", "is_active", "is_staff", "created_date")
    list_filter = ("is_active", "is_staff")
    search_fields = ("username",)
    readonly_fields = ("id", "created_date", "last_login")
    fieldsets = (
        (None, {"fields": ("username", "password")}),
        ("Activation", {"fields": ("is_active",)}),
        ("Permissions", {"fields": ("is_staff", "is_superuser", "groups",
                                    "user_permissions")}),
        ("Meta", {"fields": ("id", "created_date", "last_login")}),
    )
    add_fieldsets = ((None, {"classes": ("wide",),
        "fields": ("username", "password1", "password2")}),)
    actions = ["activate_accounts", "deactivate_accounts"]

    @admin.action(description="Activate selected accounts")
    def activate_accounts(self, request, queryset):
        queryset.update(is_active=True)

    @admin.action(description="Deactivate selected accounts")
    def deactivate_accounts(self, request, queryset):
        ids = list(queryset.values_list("id", flat=True))
        queryset.update(is_active=False)
        _close_user_sockets(ids)

    def save_model(self, request, obj, form, change):
        deactivated = (change and not obj.is_active
                       and "is_active" in form.changed_data)
        super().save_model(request, obj, form, change)
        if deactivated:
            _close_user_sockets([obj.id])
