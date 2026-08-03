from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User
from app.core.security import verify_password, get_password_hash
from app.core.auth import create_access_token
from app.core.permissions import get_current_user
from app.config import settings
from app.services.verification import issue_token, verify_token
from app.services.email import (
    get_email_sender, build_activation_email, build_email_change_email,
    activation_link,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


class LoginRequest(BaseModel):
    email: str
    password: str


class UserOut(BaseModel):
    id: int
    email: str
    full_name: str
    role: str
    is_active: bool
    university_id: int | None
    department_id: int | None
    faculty_id: int | None

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account inactive")
    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email not verified. Check your inbox or request a new activation link.",
        )
    token = create_access_token({"sub": str(user.id)})
    return TokenResponse(access_token=token, user=UserOut.model_validate(user))


@router.get("/me", response_model=UserOut)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


@router.post("/change-password", status_code=status.HTTP_200_OK)
def change_password(
    payload: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if len(payload.new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be at least 6 characters",
        )
    if not verify_password(payload.current_password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password is incorrect",
        )
    current_user.hashed_password = get_password_hash(payload.new_password)
    db.commit()
    return {"ok": True}


class ChangeEmailRequest(BaseModel):
    email: str


@router.post("/change-email")
def change_email(
    payload: ChangeEmailRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    sender=Depends(get_email_sender),
):
    new_email = payload.email.strip()
    if "@" not in new_email or "." not in new_email or " " in new_email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Enter a valid email address",
        )
    clash = db.query(User).filter(
        User.email == new_email, User.id != current_user.id).first()
    if clash:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="That email address is already in use",
        )
    raw = issue_token(db, current_user.id, "email_change",
                      timedelta(hours=settings.email_change_token_hours), new_email=new_email)
    link = f"{settings.app_base_url}/confirm-email?token={raw}"
    subject, html, text = build_email_change_email(link)
    try:
        sender.send(new_email, subject, html, text)
    except Exception:  # pragma: no cover
        import logging
        logging.getLogger("email").exception("email-change send failed for %s", new_email)
    db.commit()
    return {"ok": True, "pending_email": new_email}


class ConfirmEmailRequest(BaseModel):
    token: str


@router.post("/confirm-email", response_model=UserOut)
def confirm_email(payload: ConfirmEmailRequest, db: Session = Depends(get_db)):
    row = verify_token(db, payload.token, "email_change")
    if row is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="This confirmation link is invalid or has expired. Request a new one.")
    user = db.get(User, row.user_id)
    clash = db.query(User).filter(User.email == row.new_email, User.id != row.user_id).first()
    if user is None or clash:
        db.delete(row); db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="That email address is no longer available.")
    user.email = row.new_email
    db.delete(row)
    db.commit()
    db.refresh(user)
    return UserOut.model_validate(user)


def send_activation(db: Session, sender, user: User) -> str:
    """Issue an activation token for `user`, email the link, and return the raw
    token. Email failures are logged, not raised, so account creation is robust.
    Returns the raw token so callers (e.g. university bootstrap) can surface the
    link directly."""
    raw = issue_token(db, user.id, "activation",
                      timedelta(days=settings.activation_token_days))
    link = activation_link(raw)
    subject, html, text = build_activation_email(link)
    try:
        sender.send(user.email, subject, html, text)
    except Exception:  # pragma: no cover - delivery failures must not strand accounts
        import logging
        logging.getLogger("email").exception("activation email send failed for %s", user.email)
    return raw


class ActivateRequest(BaseModel):
    token: str
    new_password: str


@router.post("/activate", response_model=TokenResponse)
def activate(payload: ActivateRequest, db: Session = Depends(get_db)):
    if len(payload.new_password) < 6:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="New password must be at least 6 characters")
    row = verify_token(db, payload.token, "activation")
    if row is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="This activation link is invalid or has expired. Request a new one.")
    user = db.get(User, row.user_id)
    if user is None:
        db.delete(row); db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="This activation link is invalid or has expired. Request a new one.")
    user.hashed_password = get_password_hash(payload.new_password)
    user.is_verified = True
    user.is_active = True
    db.delete(row)
    db.commit()
    db.refresh(user)
    token = create_access_token({"sub": str(user.id)})
    return TokenResponse(access_token=token, user=UserOut.model_validate(user))


class ResendActivationRequest(BaseModel):
    email: str


@router.post("/resend-activation")
def resend_activation(payload: ResendActivationRequest, db: Session = Depends(get_db),
                      sender=Depends(get_email_sender)):
    user = db.query(User).filter(User.email == payload.email.strip()).first()
    if user and not user.is_verified:
        send_activation(db, sender, user)
        db.commit()
    # Always generic: do not reveal whether the account exists.
    return {"ok": True}
