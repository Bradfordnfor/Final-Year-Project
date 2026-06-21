# Further Works — Roadmap Backlog

> Source notes for **Chapter 5 (Conclusion and Further Works)** and for the
> post-presentation commercial roadmap. Items here are deliberately NOT built
> for the dissertation submission; they are future enhancements.

---

## 1. Verified email addresses (invitation / set-password flow)

**Problem.** The system currently accepts any well-formed email when an account
is created, with no proof that the address exists or is controlled by the
intended person. Account emails are admin-entered (faculty heads, lecturers,
bulk import), and there is no way to change an email after creation. For a demo
this is fine; for a marketed product it is not — accounts could be created
against fake, mistyped, or unowned addresses.

**Recommended approach — an invitation flow, not self-signup verification**,
because accounts are provisioned *by an admin for someone else*:

1. An admin creates the account with name + email + role only (no password).
2. The system emails the person a single-use **invite link**.
3. Clicking the link verifies the address *and* lets the person set their own
   password; the account stays "pending/unverified" until then.

This one change addresses three issues at once:
- proves the email is real and owned by the recipient;
- removes the current "temporary password shown once" step (more secure, less
  error-prone hand-off);
- provides the **email-change flow that is currently missing** — changing an
  email sends a confirmation link to the *new* address and only takes effect
  once that link is clicked.

**What it requires (none exists yet):**
- An outbound transactional-email capability. The system has no email sending
  today; in-app "notifications" are database rows only. Add a provider such as
  Resend, Postmark, SendGrid, Mailgun, or AWS SES.
- A `verification_token` / invitation table and the issue / verify / accept
  endpoints, with token expiry.
- Tighten format validation everywhere (the university-admin creation path uses
  a plain string rather than a validated email type).

**Optional, lower-effort realness signals:**
- Block disposable-email domains and do an MX-record lookup to reject dead
  domains.
- For the multi-tenant case, optionally restrict each university to its
  institutional email domain (e.g. only `@ubuea.cm`), which is itself a strong
  proof-of-belonging in a B2B setting.

**CH5 framing.** Present as a security/identity hardening step required before
real-world deployment, building on the existing RBAC and the notification
mechanism (which would graduate from in-app-only to email-backed).
