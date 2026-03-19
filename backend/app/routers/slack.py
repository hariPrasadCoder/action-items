from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import RedirectResponse
from app.config import settings
from app.database import get_db
import httpx

router = APIRouter()

SLACK_AUTHORIZE_URL = "https://slack.com/oauth/v2/authorize"
SLACK_TOKEN_URL = "https://slack.com/api/oauth.v2.access"

SCOPES = "chat:write,users:read,users:read.email,im:write"


@router.get("/connect")
async def slack_connect(user_id: str):
    """
    Step 1: Redirect user to Slack OAuth.
    Called by the macOS app opening a browser URL.
    """
    if not settings.slack_client_id:
        raise HTTPException(status_code=500, detail="Slack app not configured")

    url = (
        f"{SLACK_AUTHORIZE_URL}"
        f"?client_id={settings.slack_client_id}"
        f"&scope={SCOPES}"
        f"&redirect_uri={settings.slack_redirect_uri}"
        f"&state={user_id}"
    )
    return RedirectResponse(url)


@router.get("/callback")
async def slack_callback(code: str, state: str):
    """
    Step 2: Exchange code for bot token, store it, redirect back to the macOS app.
    """
    user_id = state

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            SLACK_TOKEN_URL,
            data={
                "client_id": settings.slack_client_id,
                "client_secret": settings.slack_client_secret,
                "code": code,
                "redirect_uri": settings.slack_redirect_uri,
            },
        )

    data = resp.json()
    if not data.get("ok"):
        raise HTTPException(status_code=400, detail=f"Slack OAuth failed: {data.get('error')}")

    bot_token = data["access_token"]
    slack_team_id = data.get("team", {}).get("id")

    db = get_db()

    # Store bot token on the team
    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    team_id = user.data.get("team_id") if user.data else None

    if team_id:
        db.table("teams").update({
            "slack_bot_token": bot_token,
            "slack_team_id": slack_team_id,
        }).eq("id", team_id).execute()

    # Redirect to macOS app via custom URL scheme
    return RedirectResponse(url=f"actionitems://slack-connected?team_id={team_id or ''}")


@router.get("/token")
async def slack_token(user_id: str):
    """Return the bot token for the user's team (called by macOS app after OAuth)."""
    db = get_db()
    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    team_id = user.data.get("team_id") if user.data else None
    if not team_id:
        raise HTTPException(status_code=404, detail="User has no team")

    team = db.table("teams").select("slack_bot_token").eq("id", team_id).single().execute()
    token = team.data.get("slack_bot_token") if team.data else None
    if not token:
        raise HTTPException(status_code=404, detail="No Slack token found")

    return {"bot_token": token}


@router.get("/status")
async def slack_status(user_id: str):
    """Check if the user's team has Slack connected."""
    db = get_db()
    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    team_id = user.data.get("team_id") if user.data else None
    if not team_id:
        return {"connected": False}

    team = db.table("teams").select("slack_bot_token,slack_team_id").eq("id", team_id).single().execute()
    has_token = bool(team.data and team.data.get("slack_bot_token"))
    return {"connected": has_token, "slack_team_id": team.data.get("slack_team_id") if team.data else None}
