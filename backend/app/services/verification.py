import hashlib
import secrets
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from app.models.verification import VerificationToken


def _hash(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def issue_token(db: Session, user_id: int, purpose: str, ttl: timedelta,
                new_email: str | None = None) -> str:
    """Delete any existing token of this purpose for the user, insert a fresh
    one, and return the RAW token (embed it in the emailed link). The DB stores
    only the hash. Caller is responsible for the surrounding commit."""
    db.query(VerificationToken).filter_by(user_id=user_id, purpose=purpose).delete()
    raw = secrets.token_urlsafe(32)
    db.add(VerificationToken(
        user_id=user_id,
        token_hash=_hash(raw),
        purpose=purpose,
        new_email=new_email,
        expires_at=datetime.utcnow() + ttl,
    ))
    db.flush()
    return raw


def verify_token(db: Session, raw: str, purpose: str) -> VerificationToken | None:
    """Return the matching unexpired token row, or None. Expired rows are
    deleted. On success the CALLER applies side effects then deletes the row
    (single-use)."""
    row = (
        db.query(VerificationToken)
        .filter_by(token_hash=_hash(raw), purpose=purpose)
        .first()
    )
    if row is None:
        return None
    if row.expires_at < datetime.utcnow():
        db.delete(row)
        db.flush()
        return None
    return row
