import os
import logging
from typing import Optional

logger = logging.getLogger(__name__)

FCM_CREDENTIAL_PATH = os.getenv("FCM_CREDENTIAL_PATH", "firebase-adminsdk.json")
FCM_INITIALIZED = False

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    
    if os.path.exists(FCM_CREDENTIAL_PATH):
        cred = credentials.Certificate(FCM_CREDENTIAL_PATH)
        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)
        FCM_INITIALIZED = True
        logger.info(f"Firebase Admin SDK initialized using {FCM_CREDENTIAL_PATH}")
    else:
        logger.info(f"Firebase credential not found at {FCM_CREDENTIAL_PATH}. FCM Push will run in Simulation (Mock) mode.")
except ImportError:
    logger.info("firebase-admin package is not installed. FCM Push will run in Simulation (Mock) mode.")
except Exception as e:
    logger.error(f"Failed to initialize Firebase Admin SDK: {e}. Running in Mock mode.")

def send_push_notification(token: str, title: str, body: str, data: Optional[dict] = None) -> bool:
    """
    Sends a push notification to a specific device token using FCM.
    If FCM is not initialized (e.g., key missing), simulates a successful push for testing.
    """
    if not token:
        logger.warning("FCM token is empty. Skipping notification.")
        return False
        
    if not FCM_INITIALIZED:
        logger.info("Push delivery unavailable: Firebase is not configured")
        return False
        
    try:
        from firebase_admin import messaging
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=data or {},
            token=token,
        )
        response = messaging.send(message)
        logger.info(f"Successfully sent FCM message: {response}")
        return True
    except Exception as e:
        logger.error(f"Error sending FCM message to {token}: {e}")
        return False
