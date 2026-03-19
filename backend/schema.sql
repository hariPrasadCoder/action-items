-- Flaxie database schema
-- Run this in your Supabase SQL editor

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Teams ──────────────────────────────────────────────────────────────────────

CREATE TABLE teams (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT NOT NULL,
    join_code    TEXT UNIQUE DEFAULT upper(substring(gen_random_uuid()::text, 1, 6)),
    slack_bot_token  TEXT,
    slack_team_id    TEXT,
    created_at   TIMESTAMPTZ DEFAULT now()
);

-- ── Users ──────────────────────────────────────────────────────────────────────

CREATE TABLE users (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id      TEXT UNIQUE NOT NULL,
    name           TEXT NOT NULL,
    email          TEXT,
    slack_user_id        TEXT,
    gmail_access_token   TEXT,
    gmail_refresh_token  TEXT,
    team_id              UUID REFERENCES teams(id) ON DELETE SET NULL,
    created_at           TIMESTAMPTZ DEFAULT now()
);

-- ── Action Items ───────────────────────────────────────────────────────────────

CREATE TABLE action_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id         UUID REFERENCES teams(id) ON DELETE CASCADE,
    created_by      UUID REFERENCES users(id) ON DELETE SET NULL,
    task            TEXT NOT NULL,
    status          TEXT DEFAULT 'todo' CHECK (status IN ('todo', 'inprogress', 'done', 'blocked')),
    source          TEXT NOT NULL DEFAULT 'manual',
    source_detail   TEXT DEFAULT '',
    meeting_title   TEXT,
    meeting_date    TIMESTAMPTZ,
    deadline        TEXT,
    deadline_date   TIMESTAMPTZ,
    assigned_to     JSONB,     -- { name, email, slack_user_id, is_current_user }
    assigned_by     JSONB,
    participants    JSONB,     -- array of Person
    nudge_count     INT DEFAULT 0,
    last_nudged_at  TIMESTAMPTZ,
    confidence      FLOAT DEFAULT 1.0,
    ai_draft_email  TEXT,
    ai_draft_slack  TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ── Nudge Log ──────────────────────────────────────────────────────────────────

CREATE TABLE nudge_log (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id   UUID REFERENCES action_items(id) ON DELETE CASCADE,
    sent_by   UUID REFERENCES users(id) ON DELETE SET NULL,
    channel   TEXT NOT NULL,  -- 'slack' | 'notification'
    sent_at   TIMESTAMPTZ DEFAULT now()
);

-- ── Indexes ────────────────────────────────────────────────────────────────────

CREATE INDEX idx_action_items_team_id     ON action_items(team_id);
CREATE INDEX idx_action_items_status      ON action_items(status);
CREATE INDEX idx_action_items_deadline    ON action_items(deadline_date);
CREATE INDEX idx_action_items_created_by  ON action_items(created_by);
CREATE INDEX idx_users_device_id          ON users(device_id);
CREATE INDEX idx_users_team_id            ON users(team_id);

-- ── Auto-update updated_at ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER action_items_updated_at
    BEFORE UPDATE ON action_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── Realtime (enable in Supabase Dashboard > Database > Replication too) ───────

ALTER PUBLICATION supabase_realtime ADD TABLE action_items;
