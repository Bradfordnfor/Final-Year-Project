from datetime import timedelta
from app.models.verification import VerificationToken
from app.services.verification import issue_token, verify_token, _hash


def test_issue_stores_hash_not_raw(db):
    raw = issue_token(db, user_id=1, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    row = db.query(VerificationToken).filter_by(user_id=1).one()
    assert row.token_hash == _hash(raw)
    assert row.token_hash != raw
    assert row.purpose == "activation"


def test_verify_returns_row_for_valid_token(db):
    raw = issue_token(db, user_id=2, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    row = verify_token(db, raw, "activation")
    assert row is not None and row.user_id == 2


def test_verify_wrong_purpose_returns_none(db):
    raw = issue_token(db, user_id=3, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    assert verify_token(db, raw, "email_change") is None


def test_verify_expired_returns_none_and_deletes(db):
    raw = issue_token(db, user_id=4, purpose="activation", ttl=timedelta(seconds=-1))
    db.commit()
    assert verify_token(db, raw, "activation") is None
    assert db.query(VerificationToken).filter_by(user_id=4).count() == 0


def test_reissue_replaces_prior_token(db):
    first = issue_token(db, user_id=5, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    second = issue_token(db, user_id=5, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    assert db.query(VerificationToken).filter_by(user_id=5, purpose="activation").count() == 1
    assert verify_token(db, first, "activation") is None
    assert verify_token(db, second, "activation") is not None


def test_email_change_carries_new_email(db):
    raw = issue_token(db, user_id=6, purpose="email_change",
                      ttl=timedelta(hours=24), new_email="new@x.com")
    db.commit()
    row = verify_token(db, raw, "email_change")
    assert row.new_email == "new@x.com"
