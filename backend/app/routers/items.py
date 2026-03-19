from fastapi import APIRouter, HTTPException, Depends
from app.models.schemas import ActionItemOut, ActionItemUpdate, DraftRequest, DraftResponse
from app.database import get_db
from app.auth import get_current_user
from app.ai.nodes import generate_draft

router = APIRouter()


@router.get("/", response_model=list[ActionItemOut])
async def get_items(user_id: str = Depends(get_current_user)):
    """Get all items for the user's team."""
    db = get_db()

    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    team_id = user.data.get("team_id") if user.data else None
    if not team_id:
        return []

    resp = db.table("action_items").select("*").eq("team_id", team_id).order("created_at", desc=True).execute()
    return [ActionItemOut(**_fix(i)) for i in (resp.data or [])]


@router.patch("/{item_id}", response_model=ActionItemOut)
async def update_item(item_id: str, body: ActionItemUpdate, user_id: str = Depends(get_current_user)):
    db = get_db()

    # Verify item belongs to user's team
    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    team_id = user.data.get("team_id") if user.data else None

    item_resp = db.table("action_items").select("team_id").eq("id", item_id).single().execute()
    if not item_resp.data or item_resp.data.get("team_id") != team_id:
        raise HTTPException(status_code=404, detail="Item not found")

    update_data = body.model_dump(exclude_none=True)
    if not update_data:
        raise HTTPException(status_code=400, detail="Nothing to update")

    resp = db.table("action_items").update(update_data).eq("id", item_id).execute()
    return ActionItemOut(**_fix(resp.data[0]))


@router.delete("/{item_id}")
async def delete_item(item_id: str, user_id: str = Depends(get_current_user)):
    db = get_db()
    db.table("action_items").delete().eq("id", item_id).execute()
    return {"ok": True}


@router.post("/draft", response_model=DraftResponse)
async def create_draft(body: DraftRequest, user_id: str = Depends(get_current_user)):
    """Generate an AI email or Slack draft for an action item."""
    if body.item_id:
        db = get_db()
        item_resp = db.table("action_items").select("*").eq("id", body.item_id).single().execute()
        if not item_resp.data:
            raise HTTPException(status_code=404, detail="Item not found")
        item = item_resp.data
        task = item["task"]
        assigned_to = (item.get("assigned_to") or {}).get("name")
        deadline = item.get("deadline")
        meeting_title = item.get("meeting_title")
    else:
        if not body.task:
            raise HTTPException(status_code=400, detail="Either item_id or task is required")
        task = body.task
        assigned_to = body.assigned_to_name
        deadline = body.deadline
        meeting_title = body.meeting_title

    draft = await generate_draft(
        task=task,
        draft_type=body.draft_type,
        assigned_to=assigned_to,
        deadline=deadline,
        meeting_title=meeting_title,
    )

    # Cache the draft in DB if we have a backend item ID
    if body.item_id:
        db = get_db()
        field = "ai_draft_email" if body.draft_type == "email" else "ai_draft_slack"
        db.table("action_items").update({field: draft}).eq("id", body.item_id).execute()

    return DraftResponse(draft=draft, draft_type=body.draft_type)


def _fix(item: dict) -> dict:
    """Ensure required fields have defaults."""
    from datetime import datetime
    now = datetime.utcnow()
    return {
        **item,
        "status": item.get("status") or "todo",
        "source": item.get("source") or "manual",
        "source_detail": item.get("source_detail") or "",
        "nudge_count": item.get("nudge_count") or 0,
        "confidence": item.get("confidence") or 1.0,
        "created_at": item.get("created_at") or now,
        "updated_at": item.get("updated_at") or now,
    }
