import json
import re
from datetime import date, datetime
from typing import Any
from difflib import SequenceMatcher

from langchain_anthropic import ChatAnthropic
from langchain_core.messages import HumanMessage, SystemMessage

from app.config import settings
from app.ai.prompts import (
    EXTRACT_SYSTEM, EXTRACT_USER,
    DRAFT_EMAIL_SYSTEM, DRAFT_SLACK_SYSTEM, DRAFT_USER,
)
from app.database import get_db

model = ChatAnthropic(
    model="claude-opus-4-6",
    api_key=settings.anthropic_api_key,
    max_tokens=4096,
)


# ── Helper ─────────────────────────────────────────────────────────────────────

def _fuzzy_match(name: str, team_members: list[dict]) -> dict | None:
    """Match a name string to the closest team member (threshold 0.6)."""
    if not name:
        return None
    name_lower = name.lower().strip()
    best, best_score = None, 0.0
    for member in team_members:
        member_name = member.get("name", "").lower()
        score = SequenceMatcher(None, name_lower, member_name).ratio()
        # Also check first-name-only match
        first = member_name.split()[0] if member_name else ""
        if first and name_lower == first:
            score = max(score, 0.85)
        if score > best_score:
            best, best_score = member, score
    return best if best_score >= 0.6 else None


def _parse_json(text: str) -> dict:
    """Extract JSON from a Claude response that may have markdown fences."""
    match = re.search(r"```(?:json)?\s*([\s\S]+?)```", text)
    if match:
        text = match.group(1)
    return json.loads(text.strip())


# ── LangGraph Nodes ────────────────────────────────────────────────────────────

async def load_team_context(state: dict) -> dict:
    """Fetch team members from Supabase for name-matching.
    Always includes the current user so their name can be matched even without a team."""
    user_id = state.get("user_id")
    team_id = state.get("team_id")
    db = get_db()

    # Always load the current user so we can flag is_current_user correctly
    user_resp = db.table("users").select("id,name,email,slack_user_id").eq("id", user_id).single().execute()
    current_user = user_resp.data or {}

    if not team_id:
        return {**state, "team_members": [current_user] if current_user else []}

    resp = db.table("users").select("id,name,email,slack_user_id").eq("team_id", team_id).execute()
    members = resp.data or []
    # Ensure the current user is in the list (in case they joined a team but record differs)
    if current_user and not any(m.get("id") == user_id for m in members):
        members.append(current_user)
    return {**state, "team_members": members}


async def extract_action_items(state: dict) -> dict:
    """Call Claude to extract raw action items from the notes."""
    team_members = state.get("team_members", [])
    members_list = ", ".join(m["name"] for m in team_members) if team_members else "unknown"

    system = EXTRACT_SYSTEM.format(
        today=date.today().isoformat(),
        meeting_date=state.get("meeting_date", "unknown"),
    )
    user_msg = EXTRACT_USER.format(
        meeting_title=state.get("meeting_title", ""),
        team_members_list=members_list,
        raw_notes=state["raw_notes"],
    )

    response = await model.ainvoke([
        SystemMessage(content=system),
        HumanMessage(content=user_msg),
    ])

    try:
        parsed = _parse_json(response.content)
        items = parsed.get("items", [])
        inferred_title = parsed.get("inferred_title", state.get("meeting_title", ""))
    except (json.JSONDecodeError, KeyError):
        items = []
        inferred_title = state.get("meeting_title", "")

    return {**state, "extracted_items": items, "meeting_title": inferred_title or state.get("meeting_title", "")}


async def match_people_to_roster(state: dict) -> dict:
    """Fuzzy-match extracted names to real team member records."""
    team_members = state.get("team_members", [])
    current_user_id = state.get("user_id")
    enriched = []

    for item in state.get("extracted_items", []):
        assigned_to = None
        assigned_by = None

        if to_name := item.get("assigned_to_name"):
            match = _fuzzy_match(to_name, team_members)
            if match:
                assigned_to = {
                    "name": match["name"],
                    "email": match.get("email"),
                    "slack_user_id": match.get("slack_user_id"),
                    "is_current_user": match.get("id") == current_user_id,
                }
            else:
                assigned_to = {"name": to_name, "email": None, "slack_user_id": None, "is_current_user": False}

        if by_name := item.get("assigned_by_name"):
            match = _fuzzy_match(by_name, team_members)
            if match:
                assigned_by = {
                    "name": match["name"],
                    "email": match.get("email"),
                    "slack_user_id": match.get("slack_user_id"),
                    "is_current_user": match.get("id") == current_user_id,
                }
            else:
                assigned_by = {"name": by_name, "email": None, "slack_user_id": None, "is_current_user": False}

        enriched.append({**item, "assigned_to": assigned_to, "assigned_by": assigned_by})

    return {**state, "enriched_items": enriched}


async def save_to_database(state: dict) -> dict:
    """Persist the extracted items to Supabase, skipping duplicates."""
    db = get_db()
    team_id = state.get("team_id")
    user_id = state.get("user_id")
    meeting_title = state.get("meeting_title") or ""
    saved = []

    # Fetch existing task texts for this meeting so we can skip duplicates.
    existing_tasks: list[str] = []
    if team_id and meeting_title:
        existing_resp = db.table("action_items") \
            .select("task") \
            .eq("team_id", team_id) \
            .eq("meeting_title", meeting_title) \
            .execute()
        existing_tasks = [r["task"].lower().strip() for r in (existing_resp.data or [])]

    for item in state.get("enriched_items", []):
        task_lower = item["task"].lower().strip()
        # Skip if an identical or highly similar task already exists for this meeting
        if any(
            task_lower == t or
            (len(task_lower) > 20 and (task_lower in t or t in task_lower))
            for t in existing_tasks
        ):
            continue

        row = {
            "team_id": team_id,
            "created_by": user_id,
            "task": item["task"],
            "status": "todo",
            "source": state.get("source", "manual"),
            "source_detail": meeting_title,
            "meeting_title": meeting_title or None,
            "deadline": item.get("deadline"),
            "deadline_date": item.get("deadline_date"),
            "assigned_to": item.get("assigned_to"),
            "assigned_by": item.get("assigned_by"),
            "confidence": item.get("confidence", 1.0),
        }
        resp = db.table("action_items").insert(row).execute()
        if resp.data:
            saved.append(resp.data[0])
            existing_tasks.append(task_lower)  # prevent double-insert within same batch

    return {**state, "final_items": saved}


# ── Draft generation (standalone, not a graph node) ───────────────────────────

async def generate_draft(
    task: str,
    draft_type: str,
    assigned_to: str | None,
    deadline: str | None,
    meeting_title: str | None,
    context: str = "",
) -> str:
    system = DRAFT_EMAIL_SYSTEM if draft_type == "email" else DRAFT_SLACK_SYSTEM
    user_msg = DRAFT_USER.format(
        draft_type=draft_type,
        task=task,
        assigned_to=assigned_to or "team",
        deadline=deadline or "no deadline specified",
        meeting_title=meeting_title or "our meeting",
        context=context,
    )
    response = await model.ainvoke([
        SystemMessage(content=system),
        HumanMessage(content=user_msg),
    ])
    return response.content.strip()
