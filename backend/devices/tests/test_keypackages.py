import pytest

from devices.models import KeyPackage
from devices.views import MAX_STORED_KEYPACKAGES

from .conftest import DEVICES_URL, keypackage_blob, make_device, stock_keypackages

pytestmark = pytest.mark.django_db


def keypackages_url(device_id):
    return f"{DEVICES_URL}/{device_id}/keypackages"


def blobs(count):
    return [keypackage_blob(bytes([65 + (i % 26)])) for i in range(count)]


def test_a_device_uploads_its_own_key_packages(api, active_user, device, auth_headers):
    response = api.put(keypackages_url(device.id), {"keypackages": blobs(4)},
                       format="json", **auth_headers(active_user, device))

    assert response.status_code == 200
    assert response.json()["keypackage_count"] == 4
    assert KeyPackage.objects.filter(device=device).count() == 4


def test_uploads_accumulate(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    api.put(keypackages_url(device.id), {"keypackages": blobs(2)}, format="json",
            **headers)

    response = api.put(keypackages_url(device.id), {"keypackages": blobs(3)},
                       format="json", **headers)

    assert response.json()["keypackage_count"] == 5


def test_the_hundred_stored_cap_is_enforced(api, active_user, device, auth_headers):
    stock_keypackages(device, MAX_STORED_KEYPACKAGES)

    response = api.put(keypackages_url(device.id), {"keypackages": blobs(1)},
                       format="json", **auth_headers(active_user, device))

    assert response.status_code == 409
    assert response.json()["code"] == "keypackage_limit"
    assert KeyPackage.objects.filter(device=device).count() == MAX_STORED_KEYPACKAGES


def test_a_batch_that_would_cross_the_cap_is_refused_whole(api, active_user, device,
                                                           auth_headers):
    stock_keypackages(device, MAX_STORED_KEYPACKAGES - 2)

    response = api.put(keypackages_url(device.id), {"keypackages": blobs(5)},
                       format="json", **auth_headers(active_user, device))

    assert response.status_code == 409
    # Refused whole rather than silently truncated: the client is told, not guessed at.
    assert KeyPackage.objects.filter(device=device).count() == MAX_STORED_KEYPACKAGES - 2


def test_an_off_bucket_blob_is_rejected(api, active_user, device, auth_headers):
    import base64
    response = api.put(keypackages_url(device.id),
                       {"keypackages": [base64.b64encode(b"x" * 100).decode()]},
                       format="json", **auth_headers(active_user, device))

    assert response.status_code == 400
    assert response.json()["code"] == "bad_bucket"


def test_the_count_endpoint_reports_the_store(api, active_user, device, auth_headers):
    stock_keypackages(device, 7)

    response = api.get(f"{keypackages_url(device.id)}/count",
                       **auth_headers(active_user, device))

    assert response.json()["keypackage_count"] == 7


@pytest.mark.parametrize("method, suffix, body", [
    ("put", "", {"keypackages": []}),
    ("get", "/count", None),
])
def test_a_device_cannot_touch_another_devices_key_packages(
        api, active_user, device, auth_headers, method, suffix, body):
    sibling = make_device(active_user, registration_id=43)
    headers = auth_headers(active_user, device)
    url = f"{keypackages_url(sibling.id)}{suffix}"

    response = getattr(api, method)(url, body, format="json", **headers) \
        if body is not None else getattr(api, method)(url, **headers)

    assert response.status_code == 403
    assert response.json()["code"] == "forbidden"


def test_more_than_a_hundred_in_one_request_is_rejected(api, active_user, device,
                                                        auth_headers):
    response = api.put(keypackages_url(device.id), {"keypackages": blobs(101)},
                       format="json", **auth_headers(active_user, device))

    assert response.status_code == 400
