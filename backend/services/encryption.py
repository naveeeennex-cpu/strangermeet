"""
AES-256-GCM encryption for chat messages.

All messages are encrypted before storing in the database and decrypted
when returned to authenticated users. A server-side master key (env var)
enables future admin decryption for report handling.

Format stored in DB:  base64( 12-byte nonce || ciphertext || 16-byte GCM tag )
"""

import os
import base64
import logging

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from config import settings

logger = logging.getLogger(__name__)

# ── Initialise key once at module load ──────────────────────────────────────

_key_hex = settings.MASTER_ENCRYPTION_KEY
_key: bytes | None = None
_aesgcm: AESGCM | None = None

if _key_hex and len(_key_hex) == 64:
    try:
        _key = bytes.fromhex(_key_hex)
        _aesgcm = AESGCM(_key)
    except Exception as exc:
        logger.error("Failed to initialise encryption key: %s", exc)
else:
    logger.warning(
        "MASTER_ENCRYPTION_KEY not set or invalid length (%s). "
        "Messages will be stored in PLAINTEXT.",
        len(_key_hex) if _key_hex else 0,
    )


def is_encryption_enabled() -> bool:
    return _aesgcm is not None


def encrypt_message(plaintext: str) -> str:
    """Encrypt a message string. Returns base64-encoded ciphertext."""
    if not plaintext or not _aesgcm:
        return plaintext or ""

    try:
        nonce = os.urandom(12)  # 96-bit nonce, unique per message
        ciphertext = _aesgcm.encrypt(nonce, plaintext.encode("utf-8"), None)
        # nonce (12) + ciphertext + tag (16) — all in one blob
        return base64.b64encode(nonce + ciphertext).decode("ascii")
    except Exception as exc:
        logger.error("Encryption failed: %s", exc)
        return plaintext  # Fallback to plaintext rather than losing the message


def decrypt_message(stored: str) -> str:
    """Decrypt a base64-encoded encrypted message. Returns plaintext."""
    if not stored or not _aesgcm:
        return stored or ""

    try:
        raw = base64.b64decode(stored)
        if len(raw) < 28:
            # Too short to be encrypted (12 nonce + 16 tag minimum)
            return stored
        nonce = raw[:12]
        ciphertext = raw[12:]
        plaintext = _aesgcm.decrypt(nonce, ciphertext, None)
        return plaintext.decode("utf-8")
    except Exception:
        # Not encrypted (legacy plaintext) or corrupted — return as-is
        return stored
