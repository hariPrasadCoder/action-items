from fastapi import APIRouter, HTTPException, Depends
from app.models.schemas import NudgeRequest
from app.database import get_db
from app.auth import get_current_user
from app.services.slack_service import send_slack_dm, build_nudge_message
from datetime import datetime

router = APIRouter()


@router.post("/send")
async def send_nudge(body: NudgeRequest, user_id: str = Depends(get_current_user)):
    """
    Send a nudge for a specific action item.
    channel: 'slack' → Slack DM | 'notification' → stored for client to show
    """
    db = get_db()

    # Fetch item
    item_resp = db.table("action_items").select("*").eq("id", body.item_id).single().execute()
    if not item_resp.data:
        raise HTTPException(status_code=404, detail="Item not found")
    item = item_resp.data

    # Fetch team
    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    team_id = user.data.get("team_id") if user.data else None

    sent_slack = False
    assigned_to = item.get("assigned_to") or {}
    slack_user_id = assigned_to.get("slack_user_id")

    if body.channel == "slack" and slack_user_id and team_id:
        message = body.custom_message or build_nudge_message(
            task=item["task"],
            assigned_to_name=assigned_to.get("name", ""),
            deadline=item.get("deadline"),
        )
        sent_slack = await send_slack_dm(team_id, slack_user_id, message)

    # Update nudge tracking on item
    db.table("action_items").update({
        "nudge_count": (item.get("nudge_count") or 0) + 1,
        "last_nudged_at": datetime.utcnow().isoformat(),
    }).eq("id", body.item_id).execute()

    # Log nudge
    db.table("nudge_log").insert({
        "item_id": body.item_id,
        "sent_by": user_id,
        "channel": body.channel,
    }).execute()

    return {"ok": True, "slack_sent": sent_slack}


@router.get("/pending")
async def pending_nudges(user_id: str = Depends(get_current_user)):
    """
    Returns overdue items that haven't been nudged in the last 24h.
    The macOS client polls this every 15 min to decide what to notify.
    """
    db = get_db()

    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    team_id = user.data.get("team_id") if user.data else None
    if not team_id:
        return {"items": []}

    now = datetime.utcnow()

    # Items past their deadline, not done, not nudged in last 24h
    resp = (
        db.table("action_items")
        .select("id,task,assigned_to,deadline,deadline_date,nudge_count,last_nudged_at,created_by")
        .eq("team_id", team_id)
        .neq("status", "done")
        .lt("deadline_date", now.isoformat())
        .execute()
    )

    items = resp.data or []

    # Filter: only those not nudged in the last 24 hours
    from datetime import timedelta
    cutoff = now - timedelta(hours=24)
    pending = [
        i for i in items
        if not i.get("last_nudged_at") or
        datetime.fromisoformat(i["last_nudged_at"].replace("Z", "+00:00")).replace(tzinfo=None) < cutoff
    ]

    return {"items": pending}
