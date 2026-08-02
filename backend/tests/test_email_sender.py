from unittest.mock import MagicMock, patch
from app.services.email import (
    ConsoleEmailSender, SmtpEmailSender, get_email_sender,
    build_activation_email, build_email_change_email,
)
from app.config import settings


def test_build_activation_email_contains_link():
    subject, html, text = build_activation_email("http://x/activate?token=abc")
    assert "activate" in subject.lower()
    assert "http://x/activate?token=abc" in html
    assert "http://x/activate?token=abc" in text
    assert str(settings.activation_token_days) in text
    assert str(settings.activation_token_days) in html


def test_build_email_change_email_contains_link():
    subject, html, text = build_email_change_email("http://x/confirm-email?token=abc")
    assert "http://x/confirm-email?token=abc" in text
    assert str(settings.email_change_token_hours) in text


def test_console_sender_does_not_raise():
    ConsoleEmailSender().send("a@b.com", "Subject", "<p>hi</p>", "hi")


def test_factory_returns_console_when_no_host(monkeypatch):
    monkeypatch.setattr(settings, "smtp_host", None)
    assert isinstance(get_email_sender(), ConsoleEmailSender)


def test_factory_returns_smtp_when_host_set(monkeypatch):
    monkeypatch.setattr(settings, "smtp_host", "smtp.example.com")
    assert isinstance(get_email_sender(), SmtpEmailSender)


def test_smtp_sender_builds_message_and_sends(monkeypatch):
    monkeypatch.setattr(settings, "smtp_host", "smtp.example.com")
    monkeypatch.setattr(settings, "smtp_username", "u")
    monkeypatch.setattr(settings, "smtp_password", "p")
    fake_smtp = MagicMock()
    cm = MagicMock()
    cm.__enter__.return_value = fake_smtp
    cm.__exit__.return_value = False
    with patch("app.services.email.smtplib.SMTP", return_value=cm) as smtp_ctor:
        SmtpEmailSender().send("to@x.com", "Subj", "<p>h</p>", "h")
    smtp_ctor.assert_called_once_with("smtp.example.com", 587)
    fake_smtp.starttls.assert_called_once()
    fake_smtp.login.assert_called_once_with("u", "p")
    fake_smtp.send_message.assert_called_once()


def test_smtp_sender_skips_login_without_password(monkeypatch):
    monkeypatch.setattr(settings, "smtp_host", "smtp.example.com")
    monkeypatch.setattr(settings, "smtp_username", "u")
    monkeypatch.setattr(settings, "smtp_password", None)
    fake_smtp = MagicMock()
    cm = MagicMock()
    cm.__enter__.return_value = fake_smtp
    cm.__exit__.return_value = False
    with patch("app.services.email.smtplib.SMTP", return_value=cm):
        SmtpEmailSender().send("to@x.com", "Subj", "<p>h</p>", "h")
    fake_smtp.login.assert_not_called()
    fake_smtp.send_message.assert_called_once()
