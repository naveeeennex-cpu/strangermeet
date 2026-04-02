import os
import random
import smtplib
import asyncio
from datetime import datetime, timedelta
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

from fastapi import APIRouter, HTTPException, status, Request
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests

from schemas.user import UserSignup, UserLogin, Token
from services.auth import hash_password, verify_password, create_access_token

router = APIRouter(prefix="/api/auth", tags=["auth"])

# ── Config ──────────────────────────────────────────────────────────────────

SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 465
SMTP_EMAIL = os.getenv("SMTP_EMAIL", "aptirix@gmail.com")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "nsfp awfz hkis nkop")
GOOGLE_CLIENT_ID = os.getenv(
    "GOOGLE_CLIENT_ID",
    "594414222454-leq90b0c39cobg35krqdavdirkghdoej.apps.googleusercontent.com",
)

# In-memory OTP store: email → {code, expires_at}
_otp_store: dict[str, dict] = {}

# Separate store for password-reset OTPs
_reset_otp_store: dict[str, dict] = {}


# ── Email helpers ────────────────────────────────────────────────────────────

def _build_otp_html(to_email: str, code: str, heading: str, subtext: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1.0" />
</head>
<body style="margin:0;padding:0;background-color:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" role="presentation"
         style="background:#f3f4f6;padding:48px 16px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" role="presentation"
               style="max-width:560px;background:#ffffff;border:1px solid #e5e7eb;border-radius:8px;">

          <!-- Header -->
          <tr>
            <td style="padding:28px 40px;border-bottom:1px solid #e5e7eb;">
              <span style="font-size:17px;font-weight:700;color:#111827;letter-spacing:-0.2px;">
                StrangerMeet
              </span>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding:40px 40px 32px;">
              <p style="margin:0 0 6px;font-size:22px;font-weight:700;color:#111827;line-height:1.3;">
                {heading}
              </p>
              <p style="margin:0 0 32px;font-size:14px;color:#6b7280;line-height:1.7;">
                {subtext}
              </p>

              <!-- Code block -->
              <table width="100%" cellpadding="0" cellspacing="0" role="presentation">
                <tr>
                  <td style="background:#f9fafb;border:1px solid #d1d5db;border-radius:6px;
                              padding:22px 16px;text-align:center;">
                    <span style="font-size:34px;font-weight:700;letter-spacing:16px;
                                 color:#111827;font-family:'Courier New',Courier,monospace;">
                      {code}
                    </span>
                  </td>
                </tr>
              </table>

              <p style="margin:24px 0 0;font-size:13px;color:#9ca3af;line-height:1.7;">
                This code expires in <strong style="color:#6b7280;">10 minutes</strong>.
                If you did not initiate this request, disregard this message.
                Do not share this code with anyone.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding:20px 40px;border-top:1px solid #e5e7eb;">
              <p style="margin:0;font-size:12px;color:#9ca3af;line-height:1.7;">
                Sent to {to_email} in connection with your StrangerMeet account.
                <br>StrangerMeet. All rights reserved.
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""


def _dispatch_email(to_email: str, subject: str, html: str):
    print(f"[SMTP] Sending to {to_email} | subject: {subject}")
    msg = MIMEMultipart("alternative")
    msg["From"] = f"StrangerMeet <{SMTP_EMAIL}>"
    msg["To"] = to_email
    msg["Subject"] = subject
    msg.attach(MIMEText(html, "html"))
    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.ehlo()
            server.starttls()
            server.login(SMTP_EMAIL, SMTP_PASSWORD)
            server.sendmail(SMTP_EMAIL, to_email, msg.as_string())
        print(f"[SMTP] Sent successfully to {to_email}")
    except Exception as exc:
        print(f"[SMTP ERROR] {type(exc).__name__}: {exc}")
        raise


async def _send_email_otp_mail(to_email: str, code: str):
    html = _build_otp_html(
        to_email=to_email,
        code=code,
        heading="Verify your email address",
        subtext=(
            "You requested an email verification code for your StrangerMeet account. "
            "Enter the code below in the app to continue."
        ),
    )
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(
        None, _dispatch_email, to_email,
        f"{code} — StrangerMeet verification code", html,
    )


async def _send_reset_otp_mail(to_email: str, code: str):
    html = _build_otp_html(
        to_email=to_email,
        code=code,
        heading="Password reset request",
        subtext=(
            "We received a request to reset the password for your StrangerMeet account. "
            "Enter the code below to proceed. If you did not make this request, no action is required."
        ),
    )
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(
        None, _dispatch_email, to_email,
        f"{code} — StrangerMeet password reset", html,
    )


# ── Email OTP endpoints ──────────────────────────────────────────────────────

# ── TESTING MODE: OTP bypass ────────────────────────────────────────────────
# Set to True to skip email sending and use fixed OTP "123456"
# Set back to False when SMTP / Resend is configured
_TESTING_MODE = True


@router.post("/send-email-otp")
async def send_email_otp(request: Request):
    body = await request.json()
    email = (body.get("email") or "").strip().lower()
    if not email or "@" not in email:
        raise HTTPException(status_code=400, detail="Invalid email address")

    if _TESTING_MODE:
        _otp_store[email] = {
            "code": "123456",
            "expires_at": datetime.utcnow() + timedelta(minutes=10),
        }
        print(f"[OTP] Testing mode — code 123456 for {email}")
        return {"message": "OTP sent to email"}

    code = str(random.randint(100000, 999999))
    _otp_store[email] = {
        "code": code,
        "expires_at": datetime.utcnow() + timedelta(minutes=10),
    }

    try:
        await _send_email_otp_mail(email, code)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to send email: {str(e)}")

    return {"message": "OTP sent to email"}


@router.post("/verify-email-otp")
async def verify_email_otp(request: Request):
    body = await request.json()
    email = (body.get("email") or "").strip().lower()
    code = (body.get("code") or "").strip()

    stored = _otp_store.get(email)
    if not stored:
        raise HTTPException(status_code=400, detail="No OTP found for this email. Please request a new one.")
    if datetime.utcnow() > stored["expires_at"]:
        _otp_store.pop(email, None)
        raise HTTPException(status_code=400, detail="OTP has expired. Please request a new one.")
    if stored["code"] != code:
        raise HTTPException(status_code=400, detail="Incorrect OTP. Please try again.")

    _otp_store.pop(email, None)
    return {"verified": True}


# ── Forgot / Reset password ──────────────────────────────────────────────────

@router.post("/forgot-password")
async def forgot_password(request: Request):
    pool = request.app.state.pool
    body = await request.json()
    email = (body.get("email") or "").strip().lower()
    if not email or "@" not in email:
        raise HTTPException(status_code=400, detail="Invalid email address")

    user = await pool.fetchrow("SELECT id FROM users WHERE email = $1", email)
    if not user:
        raise HTTPException(status_code=404, detail="No account found with this email")

    if _TESTING_MODE:
        _reset_otp_store[email] = {
            "code": "123456",
            "expires_at": datetime.utcnow() + timedelta(minutes=10),
        }
        print(f"[OTP] Testing mode — reset code 123456 for {email}")
        return {"message": "OTP sent to email"}

    code = str(random.randint(100000, 999999))
    _reset_otp_store[email] = {
        "code": code,
        "expires_at": datetime.utcnow() + timedelta(minutes=10),
    }

    try:
        await _send_reset_otp_mail(email, code)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to send email: {str(e)}")

    return {"message": "OTP sent to email"}


@router.post("/reset-password")
async def reset_password(request: Request):
    pool = request.app.state.pool
    body = await request.json()
    email = (body.get("email") or "").strip().lower()
    code = (body.get("code") or "").strip()
    new_password = (body.get("new_password") or "").strip()

    if len(new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    stored = _reset_otp_store.get(email)
    if not stored:
        raise HTTPException(status_code=400, detail="No OTP found. Please request a new one.")
    if datetime.utcnow() > stored["expires_at"]:
        _reset_otp_store.pop(email, None)
        raise HTTPException(status_code=400, detail="OTP has expired. Please request a new one.")
    if stored["code"] != code:
        raise HTTPException(status_code=400, detail="Incorrect OTP. Please try again.")

    _reset_otp_store.pop(email, None)
    pw_hash = hash_password(new_password)
    await pool.execute(
        "UPDATE users SET password_hash = $1 WHERE email = $2",
        pw_hash, email,
    )
    return {"message": "Password reset successfully"}


# ── Google OAuth endpoint ────────────────────────────────────────────────────

@router.post("/google")
async def google_auth(request: Request):
    pool = request.app.state.pool
    body = await request.json()
    token = body.get("id_token") or body.get("token")

    if not token:
        raise HTTPException(status_code=400, detail="Google ID token required")

    try:
        info = google_id_token.verify_oauth2_token(
            token, google_requests.Request(), GOOGLE_CLIENT_ID
        )
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired Google token")

    google_id = info["sub"]
    email = info.get("email", "").lower()
    name = info.get("name", "")
    picture = info.get("picture", "")

    # Check if user exists by google_id or email
    user = await pool.fetchrow(
        "SELECT * FROM users WHERE google_id = $1 OR (email = $2 AND email != '')",
        google_id, email,
    )

    if user:
        # Link google_id to existing email account if not already linked
        if not user.get("google_id"):
            await pool.execute(
                "UPDATE users SET google_id = $1 WHERE id = $2",
                google_id, user["id"],
            )
        access_token = create_access_token(data={"sub": str(user["id"])})
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "role": user.get("role", "customer"),
            "is_new_user": False,
        }

    # New Google user — return profile data for onboarding
    return {
        "is_new_user": True,
        "google_id": google_id,
        "email": email,
        "name": name,
        "picture": picture,
    }


# ── Standard signup / login ──────────────────────────────────────────────────

@router.post("/signup", response_model=Token, status_code=status.HTTP_201_CREATED)
async def signup(user_data: UserSignup, request: Request):
    pool = request.app.state.pool

    # Password required unless signing up via Google
    if not user_data.google_id and not user_data.password:
        raise HTTPException(status_code=400, detail="Password is required")

    existing = await pool.fetchrow("SELECT id FROM users WHERE email = $1", user_data.email)
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    username = user_data.username.lower()
    existing_username = await pool.fetchrow("SELECT id FROM users WHERE username = $1", username)
    if existing_username:
        raise HTTPException(status_code=400, detail="Username already taken")

    pw_hash = hash_password(user_data.password) if user_data.password else None

    try:
        row = await pool.fetchrow(
            """
            INSERT INTO users (name, email, password_hash, username, phone, interests,
                               role, bio, occupation, college_name, company_name,
                               designation, google_id, profile_image_url)
            VALUES ($1,$2,$3,$4,$5,$6,$7,'',$8,$9,$10,$11,$12,$13)
            RETURNING id, role
            """,
            user_data.name,
            user_data.email,
            pw_hash,
            username,
            user_data.phone,
            user_data.interests,
            user_data.role,
            user_data.occupation,
            user_data.college_name,
            user_data.company_name,
            user_data.designation,
            user_data.google_id,
            user_data.profile_image_url,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create user: {str(e)}")

    user_id = str(row["id"])
    access_token = create_access_token(data={"sub": user_id})
    return Token(access_token=access_token, role=row["role"])


@router.post("/login", response_model=Token)
async def login(user_data: UserLogin, request: Request):
    pool = request.app.state.pool

    user = await pool.fetchrow("SELECT * FROM users WHERE email = $1", user_data.email)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    if not user.get("password_hash"):
        raise HTTPException(
            status_code=400,
            detail="This account uses Google Sign-In. Please sign in with Google.",
        )

    if not verify_password(user_data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    user_id = str(user["id"])
    access_token = create_access_token(data={"sub": user_id})
    return Token(access_token=access_token, role=user.get("role", "customer"))


@router.get("/check-username/{username}")
async def check_username(username: str, request: Request):
    pool = request.app.state.pool
    existing = await pool.fetchrow("SELECT id FROM users WHERE username = $1", username.lower())
    return {"available": existing is None}
