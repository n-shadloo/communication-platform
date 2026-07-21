from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User

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
        queryset.update(is_active=False)
