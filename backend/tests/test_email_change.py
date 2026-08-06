import re
from tests.conftest import make_university


def _admin_headers(client, auth_headers):
    make_university(client, auth_headers)
    tok = client.post("/auth/login", json={
        "email": "admin_ub@test.com", "password": "password123"}).json()["access_token"]
    return {"Authorization": f"Bearer {tok}"}


def _token_from_emails(sent_emails):
    for m in sent_emails:
        match = re.search(r"/#/confirm-email\?token=(\S+)", m["text"])
        if match:
            return match.group(1)
    return None


def test_change_email_sends_confirmation_and_does_not_swap(client, auth_headers, sent_emails):
    headers = _admin_headers(client, auth_headers)
    r = client.post("/auth/change-email", json={"email": "brandnew@test.com"}, headers=headers)
    assert r.status_code == 200
    assert r.json()["pending_email"] == "brandnew@test.com"
    # confirmation went to the NEW address
    assert any(m["to"] == "brandnew@test.com" for m in sent_emails)
    # current email unchanged
    me = client.get("/auth/me", headers=headers).json()
    assert me["email"] == "admin_ub@test.com"


def test_confirm_email_swaps_address(client, auth_headers, sent_emails):
    headers = _admin_headers(client, auth_headers)
    client.post("/auth/change-email", json={"email": "confirmed@test.com"}, headers=headers)
    token = _token_from_emails(sent_emails)
    assert token
    r = client.post("/auth/confirm-email", json={"token": token})
    assert r.status_code == 200
    assert r.json()["email"] == "confirmed@test.com"


def test_confirm_email_rejects_bad_token(client, auth_headers, sent_emails):
    r = client.post("/auth/confirm-email", json={"token": "nope"})
    assert r.status_code == 400
