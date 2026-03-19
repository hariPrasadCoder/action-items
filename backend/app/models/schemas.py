from pydantic import BaseModel
from typing import Optional
from datetime import datetime


# ── Auth ──────────────────────────────────────────────────────────────────────

class DeviceRegisterRequest(BaseModel):
    device_id: str          # UUID generated on first app launch
    name: str
    email: Optional[str] = None


class AuthResponse(BaseModel):
    token: str
    user_id: str
    team_id: Optional[str] = None
    team_join_code: Optional[str] = None


# ── People ────────────────────────────────────────────────────────────────────

class Person(BaseModel):
    name: str
    email: Optional[str] = None
    slack_user_id: Optional[str] = None
    is_current_user: bool = False


# ── Items ─────────────────────────────────────────────────────────────────────

class ActionItemCreate(BaseModel):
    task: str
    source: str = "manual"
    source_detail: str = ""
    meeting_title: Optional[str] = None
    meeting_date: Optional[datetime] = None
    deadline: Optional[str] = None
    deadline_date: Optional[datetime] = None
    assigned_to: Optional[Person] = None
    assigned_by: Optional[Person] = None
    participants: Optional[list[Person]] = None
    confidence: float = 1.0


class ActionItemUpdate(BaseModel):
    status: Optional[str] = None
    task: Optional[str] = None
    deadline: Optional[str] = None
    deadline_date: Optional[datetime] = None


class ActionItemOut(BaseModel):
    id: str
    team_id: str
    created_by: Optional[str] = None
    task: str
    status: str
    source: str
    source_detail: str
    meeting_title: Optional[str] = None
    meeting_date: Optional[datetime] = None
    deadline: Optional[str] = None
    deadline_date: Optional[datetime] = None
    assigned_to: Optional[dict] = None
    assigned_by: Optional[dict] = None
    participants: Optional[list] = None
    nudge_count: int = 0
    last_nudged_at: Optional[datetime] = None
    confidence: float = 1.0
    ai_draft_email: Optional[str] = None
    ai_draft_slack: Optional[str] = None
    created_at: datetime
    updated_at: datetime


# ── Notes processing ──────────────────────────────────────────────────────────

class ProcessNotesRequest(BaseModel):
    raw_notes: str
    meeting_title: str = ""
    source: str = "manual"   # granola | fireflies | otter | screen | manual


class ProcessNotesResponse(BaseModel):
    items: list[ActionItemOut]
    meeting_title: str
    item_count: int


# ── Teams ─────────────────────────────────────────────────────────────────────

class CreateTeamRequest(BaseModel):
    name: str


class JoinTeamRequest(BaseModel):
    join_code: str


class TeamOut(BaseModel):
    id: str
    name: str
    join_code: str
    member_count: int = 0


# ── Drafts ────────────────────────────────────────────────────────────────────

class DraftRequest(BaseModel):
    item_id: Optional[str] = None   # if provided, look up item from DB
    draft_type: str                 # "email" | "slack"
    # Inline fields used when item_id is not provided (e.g. unsynced local items)
    task: Optional[str] = None
    assigned_to_name: Optional[str] = None
    deadline: Optional[str] = None
    meeting_title: Optional[str] = None


class DraftResponse(BaseModel):
    draft: str
    draft_type: str


# ── Nudge ─────────────────────────────────────────────────────────────────────

class NudgeRequest(BaseModel):
    item_id: str
    channel: str = "slack"   # "slack" | "notification"
    custom_message: Optional[str] = None
