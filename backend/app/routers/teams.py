from fastapi import APIRouter, HTTPException, Depends
from app.models.schemas import CreateTeamRequest, JoinTeamRequest, TeamOut
from app.database import get_db
from app.auth import get_current_user

router = APIRouter()


@router.post("/create", response_model=TeamOut)
async def create_team(body: CreateTeamRequest, user_id: str = Depends(get_current_user)):
    db = get_db()

    # Check user doesn't already have a team
    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    if user.data and user.data.get("team_id"):
        raise HTTPException(status_code=400, detail="You're already in a team")

    # Create team
    team_resp = db.table("teams").insert({"name": body.name}).execute()
    if not team_resp.data:
        raise HTTPException(status_code=500, detail="Failed to create team")
    team = team_resp.data[0]

    # Assign user to team
    db.table("users").update({"team_id": team["id"]}).eq("id", user_id).execute()

    return TeamOut(id=team["id"], name=team["name"], join_code=team["join_code"], member_count=1)


@router.post("/join", response_model=TeamOut)
async def join_team(body: JoinTeamRequest, user_id: str = Depends(get_current_user)):
    db = get_db()

    team_resp = db.table("teams").select("*").eq("join_code", body.join_code.upper()).execute()
    if not team_resp.data:
        raise HTTPException(status_code=404, detail="Team not found — check your join code")
    team = team_resp.data[0]

    # Add user to team
    db.table("users").update({"team_id": team["id"]}).eq("id", user_id).execute()

    # Count members
    count_resp = db.table("users").select("id", count="exact").eq("team_id", team["id"]).execute()
    member_count = count_resp.count or 1

    return TeamOut(id=team["id"], name=team["name"], join_code=team["join_code"], member_count=member_count)


@router.get("/me", response_model=TeamOut)
async def get_my_team(user_id: str = Depends(get_current_user)):
    db = get_db()

    user = db.table("users").select("team_id").eq("id", user_id).single().execute()
    if not user.data or not user.data.get("team_id"):
        raise HTTPException(status_code=404, detail="Not in a team")

    team_id = user.data["team_id"]
    team = db.table("teams").select("*").eq("id", team_id).single().execute()
    count_resp = db.table("users").select("id", count="exact").eq("team_id", team_id).execute()

    t = team.data
    return TeamOut(id=t["id"], name=t["name"], join_code=t["join_code"], member_count=count_resp.count or 0)
