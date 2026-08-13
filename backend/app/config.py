from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str
    test_database_url: str = "sqlite:///./test.db"
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440

    # Allowed browser origins for CORS: comma-separated list, or "*" for any.
    # In production set this to your frontend URL, e.g. "https://app.example.com".
    allowed_origins: str = "*"

    # Email delivery (absence of smtp_host selects the console backend)
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_from: str = "no-reply@timetabling.local"
    smtp_use_tls: bool = True
    app_base_url: str = "http://localhost:8080"
    activation_token_days: int = 7
    email_change_token_hours: int = 24

    class Config:
        env_file = ".env"


settings = Settings()
