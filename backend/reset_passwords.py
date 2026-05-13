import sys, os
sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal
from app.models.user import User
from app.core.security import get_password_hash

ACCOUNTS = [
    ("superadmin@ub.cm", "super123"),
    ("admin@ub.cm",      "admin123"),
    ("fethead@ub.cm",    "fethead123"),
    ("officer@ub.cm",    "officer123"),
    ("lecturer@ub.cm",   "lecturer123"),
    ("student@ub.cm",    "student123"),
]

def reset():
    db = SessionLocal()
    try:
        for email, password in ACCOUNTS:
            user = db.query(User).filter(User.email == email).first()
            if user:
                user.hashed_password = get_password_hash(password)
                print(f"  Reset: {email}")
            else:
                print(f"  NOT FOUND: {email}")
        db.commit()
        print("Done.")
    finally:
        db.close()

if __name__ == "__main__":
    reset()
