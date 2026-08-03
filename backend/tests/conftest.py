import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.database import Base, get_db
from app.models.user import User
from app.core.security import get_password_hash

TEST_DATABASE_URL = "sqlite:///./test.db"

engine = create_engine(TEST_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db


@pytest.fixture(autouse=True)
def setup_db():
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture
def admin_user(db):
    user = User(
        email="admin@test.com",
        hashed_password=get_password_hash("password123"),
        full_name="Test Admin",
        role="super_admin",
        is_active=True,
        is_verified=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@pytest.fixture
def admin_token(client, admin_user):
    response = client.post("/auth/login", json={
        "email": "admin@test.com",
        "password": "password123",
    })
    return response.json()["access_token"]


@pytest.fixture
def auth_headers(admin_token):
    return {"Authorization": f"Bearer {admin_token}"}


def activate_user(email, password="password123"):
    """Test helper: mark an account verified and give it a known password, so a
    test that created it via the API can then log in."""
    dbs = TestingSessionLocal()
    try:
        u = dbs.query(User).filter(User.email == email).first()
        if u:
            u.is_verified = True
            u.hashed_password = get_password_hash(password)
            dbs.commit()
    finally:
        dbs.close()


def make_university(client, auth_headers, name="UB", slug="ub"):
    """Create a university (and its first admin) via the current API and return the JSON.

    POST /universities/ now bundles the first admin account, so tests must send
    admin_* fields. The admin email is derived from the slug to stay unique when
    a single test creates more than one university.
    """
    resp = client.post("/universities/", json={
        "name": name,
        "slug": slug,
        "admin_full_name": f"{slug.upper()} Admin",
        "admin_email": f"admin_{slug}@test.com",
        "admin_password": "password123",
    }, headers=auth_headers).json()
    activate_user(f"admin_{slug}@test.com")
    return resp


@pytest.fixture
def sent_emails():
    """Capture emails instead of sending. Yields a list of dicts:
    {to, subject, html, text}."""
    from app.services.email import get_email_sender
    box = []

    class _Capture:
        def send(self, to, subject, html, text):
            box.append({"to": to, "subject": subject, "html": html, "text": text})

    app.dependency_overrides[get_email_sender] = lambda: _Capture()
    yield box
    app.dependency_overrides.pop(get_email_sender, None)
