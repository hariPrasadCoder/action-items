from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.routers import auth, notes, items, teams, slack, nudge, gmail


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Warm up the LangGraph pipeline on startup
    from app.ai.pipeline import get_pipeline
    get_pipeline()
    print("✨ Flaxie backend ready")
    yield


app = FastAPI(
    title="Flaxie API",
    version="0.1.0",
    description="Backend for Flaxie — team meeting action tracker",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router,   prefix="/auth",  tags=["auth"])
app.include_router(notes.router,  prefix="/notes", tags=["notes"])
app.include_router(items.router,  prefix="/items", tags=["items"])
app.include_router(teams.router,  prefix="/teams", tags=["teams"])
app.include_router(slack.router,  prefix="/slack", tags=["slack"])
app.include_router(nudge.router,  prefix="/nudge", tags=["nudge"])
app.include_router(gmail.router,  prefix="/gmail", tags=["gmail"])


@app.get("/health")
def health():
    return {"status": "ok", "service": "flaxie-backend"}
