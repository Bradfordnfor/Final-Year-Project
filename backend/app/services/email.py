import logging
import smtplib
from email.message import EmailMessage
from app.config import settings

logger = logging.getLogger("email")


class ConsoleEmailSender:
    """Dev/test backend: logs the message (including the link) instead of sending."""

    def send(self, to: str, subject: str, html: str, text: str) -> None:
        logger.info("EMAIL (console)\n  to: %s\n  subject: %s\n%s", to, subject, text)


class SmtpEmailSender:
    """Production backend: sends via SMTP using the configured settings."""

    def send(self, to: str, subject: str, html: str, text: str) -> None:
        msg = EmailMessage()
        msg["From"] = settings.smtp_from
        msg["To"] = to
        msg["Subject"] = subject
        msg.set_content(text)
        msg.add_alternative(html, subtype="html")
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
            if settings.smtp_use_tls:
                server.starttls()
            if settings.smtp_username and settings.smtp_password:
                server.login(settings.smtp_username, settings.smtp_password)
            server.send_message(msg)


def get_email_sender():
    """FastAPI dependency: real SMTP when configured, console otherwise."""
    if settings.smtp_host:
        return SmtpEmailSender()
    return ConsoleEmailSender()


def activation_link(raw: str) -> str:
    """Build the activation URL for a raw token, so every caller (the
    invitation email and the university-bootstrap response) constructs it the
    same way and cannot drift."""
    return f"{settings.app_base_url}/activate?token={raw}"


def build_activation_email(link: str) -> tuple[str, str, str]:
    subject = "Activate your timetabling account"
    days = settings.activation_token_days
    text = (
        "Welcome. To activate your account and set your password, open this link:\n"
        f"{link}\n\nThe link expires in {days} days."
    )
    html = (
        "<p>Welcome. To activate your account and set your password, "
        f'click <a href="{link}">this link</a>.</p>'
        f"<p>The link expires in {days} days.</p>"
    )
    return subject, html, text


def build_email_change_email(link: str) -> tuple[str, str, str]:
    subject = "Confirm your new email address"
    hours = settings.email_change_token_hours
    text = (
        "Confirm this as your new email address by opening this link:\n"
        f"{link}\n\nThe link expires in {hours} hours. If you did not request this, ignore it."
    )
    html = (
        "<p>Confirm this as your new email address by clicking "
        f'<a href="{link}">this link</a>.</p>'
        f"<p>The link expires in {hours} hours. If you did not request this, ignore it.</p>"
    )
    return subject, html, text
