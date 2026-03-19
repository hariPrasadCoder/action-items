from fastapi import APIRouter, HTTPException
from fastapi.responses import RedirectResponse
from app.config import settings
from app.database import get_db
import httpx

router = APIRouter()

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
SCOPES = "https://www.googleapis.com/auth/gmail.readonly"


@router.get("/connect")
async def gmail_connect(user_id: str):
    """Step 1: Redirect user to Google OAuth."""
    if not settings.google_client_id:
        raise HTTPException(status_code=500, detail="Gmail app not configured")

    url = (
        f"{GOOGLE_AUTH_URL}"
        f"?client_id={settings.google_client_id}"
        f"&redirect_uri={settings.google_redirect_uri}"
        f"&response_type=code"
        f"&scope={SCOPES}"
        f"&access_type=offline"
        f"&prompt=consent"
        f"&state={user_id}"
    )
    return RedirectResponse(url)


@router.get("/callback")
async def gmail_callback(code: str, state: str):
    """Step 2: Exchange code for tokens, store them, redirect back to macOS app."""
    user_id = state

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            GOOGLE_TOKEN_URL,
            data={
                "code": code,
                "client_id": settings.google_client_id,
                "client_secret": settings.google_client_secret,
                "redirect_uri": settings.google_redirect_uri,
                "grant_type": "authorization_code",
            },
        )

    data = resp.json()
    if "error" in data:
        raise HTTPException(status_code=400, detail=f"Google OAuth failed: {data.get('error_description', data['error'])}")

    access_token = data["access_token"]
    refresh_token = data.get("refresh_token")

    db = get_db()
    db.table("users").update({
        "gmail_access_token": access_token,
        "gmail_refresh_token": refresh_token,
    }).eq("id", user_id).execute()

    return RedirectResponse(url="actionitems://gmail-connected")


@router.get("/tokens")
async def gmail_tokens(user_id: str):
    """Return stored Gmail tokens for the user (called by macOS app on launch/reconnect)."""
    db = get_db()
    user = db.table("users").select("gmail_access_token,gmail_refresh_token").eq("id", user_id).single().execute()
    if not user.data:
        raise HTTPException(status_code=404, detail="User not found")

    return {
        "access_token": user.data.get("gmail_access_token"),
        "refresh_token": user.data.get("gmail_refresh_token"),
    }


@router.get("/status")
async def gmail_status(user_id: str):
    """Check if the user has Gmail connected."""
    db = get_db()
    user = db.table("users").select("gmail_access_token").eq("id", user_id).single().execute()
    has_token = bool(user.data and user.data.get("gmail_access_token"))
    return {"connected": has_token}


@router.post("/refresh")
async def gmail_refresh(body: dict):
    """Exchange a refresh token for a new access token (proxied to keep client_secret server-side)."""
    refresh_token = body.get("refresh_token")
    if not refresh_token:
        raise HTTPException(status_code=400, detail="refresh_token required")

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            GOOGLE_TOKEN_URL,
            data={
                "refresh_token": refresh_token,
                "client_id": settings.google_client_id,
                "client_secret": settings.google_client_secret,
                "grant_type": "refresh_token",
            },
        )

    data = resp.json()
    if "error" in data:
        raise HTTPException(status_code=401, detail=f"Token refresh failed: {data.get('error')}")

    return {"access_token": data["access_token"]}


@router.delete("/disconnect")
async def gmail_disconnect(user_id: str):
    """Remove stored Gmail tokens."""
    db = get_db()
    db.table("users").update({
        "gmail_access_token": None,
        "gmail_refresh_token": None,
    }).eq("id", user_id).execute()
    return {"ok": True}
