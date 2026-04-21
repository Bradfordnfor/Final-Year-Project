from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from app.database import get_db
from app.core.auth import decode_access_token
from app.models.user import User

bearer_scheme = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    token = credentials.credentials
    payload = decode_access_token(token)
    if payload is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user_id: int = payload.get("sub")
    if user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user = db.get(User, int(user_id))
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


def require_roles(*roles: str):
    def dependency(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
        return current_user
    return dependency


def require_super_admin(user: User = Depends(get_current_user)) -> User:
    return require_roles("super_admin")(user)


def require_university_admin(user: User = Depends(get_current_user)) -> User:
    return require_roles("super_admin", "university_admin")(user)


def require_faculty_head(user: User = Depends(get_current_user)) -> User:
    return require_roles("super_admin", "university_admin", "faculty_head")(user)


def require_timetable_officer(user: User = Depends(get_current_user)) -> User:
    return require_roles(
        "super_admin", "university_admin", "faculty_head", "timetable_officer"
    )(user)
