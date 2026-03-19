from fastapi import APIRouter, HTTPException
from app.models.schemas import DeviceRegisterRequest, AuthResponse
from app.database import get_db
from app.auth import create_token

router = APIRouter()


@router.post("/device", response_model=AuthResponse)
async def register_device(body: DeviceRegisterRequest):
    """
    Register a device (first launch) or log in (subsequent launches).
    Returns a long-lived JWT. No password needed.
    """
    db = get_db()

    # Check if device already registered
    existing = db.table("users").select("*").eq("device_id", body.device_id).execute()

    if existing.data:
        user = existing.data[0]
    else:
        # Create new user
        insert = db.table("users").insert({
            "device_id": body.device_id,
            "name": body.name,
            "email": body.email,
        }).execute()

        if not insert.data:
            raise HTTPException(status_code=500, detail="Failed to create user")
        user = insert.data[0]

    token = create_token(user["id"])

    # Fetch team info if user has one
    join_code = None
    if user.get("team_id"):
        team = db.table("teams").select("join_code").eq("id", user["team_id"]).single().execute()
        join_code = team.data.get("join_code") if team.data else None

    return AuthResponse(
        token=token,
        user_id=user["id"],
        team_id=user.get("team_id"),
        team_join_code=join_code,
    )
