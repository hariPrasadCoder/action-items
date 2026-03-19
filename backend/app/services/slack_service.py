from slack_sdk.web.async_client import AsyncWebClient
from slack_sdk.errors import SlackApiError
from app.database import get_db


async def _get_bot_token(team_id: str) -> str | None:
    db = get_db()
    resp = db.table("teams").select("slack_bot_token").eq("id", team_id).single().execute()
    return resp.data.get("slack_bot_token") if resp.data else None


async def send_slack_dm(team_id: str, slack_user_id: str, message: str) -> bool:
    """Send a DM to a user via the team's Slack bot token."""
    token = await _get_bot_token(team_id)
    if not token:
        return False

    client = AsyncWebClient(token=token)
    try:
        # Open a DM channel
        dm_resp = await client.conversations_open(users=[slack_user_id])
        channel_id = dm_resp["channel"]["id"]
        # Send message
        await client.chat_postMessage(channel=channel_id, text=message)
        return True
    except SlackApiError:
        return False


async def lookup_slack_user(team_id: str, email: str) -> str | None:
    """Return the Slack user ID for a given email."""
    token = await _get_bot_token(team_id)
    if not token:
        return None

    client = AsyncWebClient(token=token)
    try:
        resp = await client.users_lookupByEmail(email=email)
        return resp["user"]["id"]
    except SlackApiError:
        return None


def build_nudge_message(task: str, assigned_to_name: str, deadline: str | None) -> str:
    deadline_text = f" (due: {deadline})" if deadline else ""
    return (
        f"Hey! 👋 Just a quick nudge from Flaxie — you have a pending action item{deadline_text}:\n\n"
        f"*{task}*\n\n"
        "Could you give a quick status update? Thanks! ✨"
    )
