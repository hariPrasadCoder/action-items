from fastapi import APIRouter, HTTPException, Depends
from app.models.schemas import ProcessNotesRequest, ProcessNotesResponse, ActionItemOut
from app.database import get_db
from app.auth import get_current_user
from app.ai.pipeline import get_pipeline
from datetime import datetime, timezone

router = APIRouter()


@router.post("/process", response_model=ProcessNotesResponse)
async def process_notes(body: ProcessNotesRequest, user_id: str = Depends(get_current_user)):
    """
    Main endpoint: send meeting notes → Flaxie extracts action items via LangGraph.
    Returns saved items (or unsaved if user has no team yet).
    """
    db = get_db()

    # Get user's team
    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    team_id = user.data.get("team_id") if user.data else None

    pipeline = get_pipeline()
    result = await pipeline.ainvoke({
        "raw_notes": body.raw_notes,
        "meeting_title": body.meeting_title,
        "meeting_date": datetime.utcnow().date().isoformat(),
        "source": body.source,
        "user_id": user_id,
        "team_id": team_id,
        "team_members": [],
        "extracted_items": [],
        "enriched_items": [],
        "final_items": [],
        "error": None,
    })

    items = result.get("final_items") or result.get("enriched_items") or []
    meeting_title = result.get("meeting_title", body.meeting_title)

    return ProcessNotesResponse(
        items=[ActionItemOut(**_normalize(i)) for i in items if _normalize(i)],
        meeting_title=meeting_title,
        item_count=len(items),
    )


def _normalize(item: dict) -> dict | None:
    """Map pipeline output dict to ActionItemOut-compatible dict."""
    if not item.get("task"):
        return None
    now = datetime.now(timezone.utc)
    return {
        "id": item.get("id", ""),
        "team_id": item.get("team_id", ""),
        "created_by": item.get("created_by"),
        "task": item["task"],
        "status": item.get("status", "todo"),
        "source": item.get("source", "manual"),
        "source_detail": item.get("source_detail", ""),
        "meeting_title": item.get("meeting_title"),
        "meeting_date": item.get("meeting_date"),
        "deadline": item.get("deadline"),
        "deadline_date": item.get("deadline_date"),
        "assigned_to": item.get("assigned_to"),
        "assigned_by": item.get("assigned_by"),
        "participants": item.get("participants"),
        "nudge_count": item.get("nudge_count", 0),
        "last_nudged_at": item.get("last_nudged_at"),
        "confidence": item.get("confidence", 1.0),
        "ai_draft_email": item.get("ai_draft_email"),
        "ai_draft_slack": item.get("ai_draft_slack"),
        "created_at": item.get("created_at", now),
        "updated_at": item.get("updated_at", now),
    }
