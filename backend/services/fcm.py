"""
Firebase Cloud Messaging (FCM) service.
Sends push notifications to mobile devices via Firebase Admin SDK.

Setup:
  1. Go to Firebase Console → Project Settings → Service Accounts
  2. Click "Generate new private key" → download the JSON file
  3. On Railway: add env var FIREBASE_SERVICE_ACCOUNT_JSON = <contents of the JSON file>
"""

import os
import json
import logging

logger = logging.getLogger(__name__)

_firebase_app = None

# Fallback credentials (used when FIREBASE_SERVICE_ACCOUNT_JSON env var is not set)
_FALLBACK_SERVICE_ACCOUNT = {
    "type": "service_account",
    "project_id": "exstranger-a6fc3",
    "private_key_id": "7f760ad17b9e962e824ebe35ccc17ce4ee78fbf0",
    "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDJ3FTHt8aqM/tV\njb2bjzoRzMzOvjW8WYlkfkJv0PUhe9eunMpR0ztLfPCMoOVOOSu0aLA7SXBEF3MC\nqSzVqLMiBs78a+9z0Q+K3WI/oIwMf/2udoMp4iNQNiRSSOwLtCH8grBPVeGz4DDG\nugMCfxTyUsJegQY/qjqRDS/65nj88CFSxWsmkP8tVgk4hlcrH+QuhcEnW0tpZad3\nvtvQX2L9jZPNpRqAvax7iFZD0qkKoXQXlMUUpBl+HbStVAp55x06QFiELUJqHQQx\nIFLXP1vKxbScHuDVldsGuEMVNaf6M9RiEipfYKMr+O2JecTc1Ml7LEJQZHjy0+ez\nKnf18JR7AgMBAAECggEALRzbK6lEMmycmnGrctUPFsRM71VuH/JotLdM9L1f00Rg\nnur2glPxV/0Lq3oX1SQMwux0mkNe3jDZaLpTRUrHAe9AmgQrRxhtX0z7tJmWQwLl\nuHRO+vDJkJcRBfy7GCCBSfQRICHi57bOX9NZcdjh3wgk3Ub7lQXfweQPGYUhe/Fu\n7LDguk3a52yGW/IfUZ/SZwsWmMtOUReqRmJj5+QjORPbnUalHtq/Vm7GYAMEAW0i\ntS6d/qmrulOHWPmbi25gw0u5QTPPoMvO5SdSc/6cL+doSvcJC5lmACpjY6dccsWY\nQVYY9coNovYmdVujyP0YLa1fBwTpAFfkGmZDZTl3FQKBgQDrmi9M+malkktagxmW\nAcehPkfzk3xhQGlfjpvrQCtH+MNI1eE+kPXznxhjRaJm/rAuEFFSZ3qksoKjQJ9p\n4cE9Nve5iQGM8uymSrjfFPkNpi3efdhOm3avJRyP0vsMB8tymkPkZp207sGjo6UL\n5xNNJS+66Je5DvwOK+pNavNbDQKBgQDbVk7MRgGNJ2Dj/h5ZiRKOcsEOVD3fta36\nrAdK0Vhuyi7g8v0n3RSUr57JUajMeCHliEaie/K3GbIO32jXASSjsPN5JmleFF28\n41Uz4vnXjy0DO5KhCawQgjrDWNVGe6qQah+Gq7B99Nu++lcgrzJnMxSyvtpbNX8I\ng6/2dzkrpwKBgQCibVP64A7wSyGELynujx+P/J4iQSXY7k03Qdwgnca5AbmwdzOo\nrMvDv4VSu2kxVJklyL4n74tQDHmgDydYGfndOA4lbV0STU/1fUJjGdRyIoUxBNWh\nq/Bw40cDqNLHAoCya8QurMhBOvFo3aMlx5M49lAnrb8cKEaBhqkr4nYP6QKBgCUF\nnmtQbbabrPkOzaSjRGSS7g8zHPaDvggPvXNdfqXErsD9gsmVwYGPWyf0Bp/srxwF\nMpb+gOtzBOEJyLJx2PNgTNhoKWTd3yyg2qLVbwJ5gkmHZqqT7V0j/jM27VjmStXx\nc7zRggrgp67Gpqo3qDRPJPE+0bCPiQ+w2qSpXxcFAoGAc1AGUdm11o0q7Yyvb7co\nYUSR6Wm5sa3e/jSnLDcV8fmIlalUJVqsH0YF9rDKqjFLdcTCfAtyUwadUhttl5a2\nwb/uJXQVFbzGOAgqSZtbyShBcWpNIVrxfqcAU1ff3//BqDscIRaDHQHVhAZRdgeV\nl/Z9c8hkArkFGW+cwxDjfV8=\n-----END PRIVATE KEY-----\n",
    "client_email": "firebase-adminsdk-fbsvc@exstranger-a6fc3.iam.gserviceaccount.com",
    "client_id": "112570690668489631505",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40exstranger-a6fc3.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com",
}


def _get_app():
    """Lazily initialise Firebase Admin SDK (only once)."""
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    try:
        import firebase_admin
        from firebase_admin import credentials

        raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON", "")
        service_account = json.loads(raw) if raw else _FALLBACK_SERVICE_ACCOUNT

        cred = credentials.Certificate(service_account)
        _firebase_app = firebase_admin.initialize_app(cred)
        logger.info("[FCM] Firebase Admin SDK initialised")
        return _firebase_app

    except Exception as e:
        logger.error(f"[FCM] Failed to initialise Firebase Admin SDK: {e}")
        return None


async def send_push(
    *,
    token: str,
    title: str,
    body: str,
    data: dict | None = None,
) -> bool:
    """
    Send a single FCM push notification.
    Returns True on success, False on failure.
    Silently skips if FCM is not configured or token is empty.
    """
    if not token:
        return False

    app = _get_app()
    if app is None:
        return False

    try:
        from firebase_admin import messaging

        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=token,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    sound="default",
                    channel_id="stranger_meet_default",
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default"),
                ),
            ),
        )
        response = messaging.send(msg)
        logger.info(f"[FCM] Push sent: {response}")
        return True

    except Exception as e:
        logger.error(f"[FCM] Failed to send push to token {token[:20]}...: {e}")
        return False


async def send_push_multicast(
    *,
    tokens: list[str],
    title: str,
    body: str,
    data: dict | None = None,
) -> int:
    """
    Send push to multiple tokens. Returns number of successes.
    """
    tokens = [t for t in tokens if t]
    if not tokens:
        return 0

    app = _get_app()
    if app is None:
        return 0

    try:
        from firebase_admin import messaging

        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            tokens=tokens,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    sound="default",
                    channel_id="stranger_meet_default",
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default"),
                ),
            ),
        )
        response = messaging.send_each_for_multicast(message)
        logger.info(f"[FCM] Multicast: {response.success_count}/{len(tokens)} sent")
        return response.success_count

    except Exception as e:
        logger.error(f"[FCM] Multicast failed: {e}")
        return 0
