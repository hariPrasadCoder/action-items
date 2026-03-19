from typing import TypedDict, Optional
from langgraph.graph import StateGraph, END
from app.ai.nodes import (
    load_team_context,
    extract_action_items,
    match_people_to_roster,
    save_to_database,
)


class FlaxieState(TypedDict):
    # ── Inputs ──────────────────────────────────────────────────────────────
    raw_notes: str
    meeting_title: str
    meeting_date: Optional[str]
    source: str          # granola | fireflies | otter | screen | manual
    user_id: str
    team_id: Optional[str]

    # ── Intermediate ─────────────────────────────────────────────────────────
    team_members: list[dict]
    extracted_items: list[dict]
    enriched_items: list[dict]

    # ── Output ───────────────────────────────────────────────────────────────
    final_items: list[dict]
    error: Optional[str]


def _should_save(state: FlaxieState) -> str:
    """Only persist if we have a team_id (otherwise return items without saving)."""
    return "save" if state.get("team_id") else "done"


def build_pipeline():
    graph = StateGraph(FlaxieState)

    graph.add_node("load_team", load_team_context)
    graph.add_node("extract", extract_action_items)
    graph.add_node("match_people", match_people_to_roster)
    graph.add_node("save", save_to_database)

    graph.set_entry_point("load_team")
    graph.add_edge("load_team", "extract")
    graph.add_edge("extract", "match_people")
    graph.add_conditional_edges("match_people", _should_save, {"save": "save", "done": END})
    graph.add_edge("save", END)

    return graph.compile()


# Singleton
_pipeline = None


def get_pipeline():
    global _pipeline
    if _pipeline is None:
        _pipeline = build_pipeline()
    return _pipeline
