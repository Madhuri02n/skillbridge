-- SkillBridge AI database schema

CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    name          VARCHAR(150)  NOT NULL,
    email         VARCHAR(255)  UNIQUE NOT NULL,
    password_hash TEXT          NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analyses (
    id                SERIAL PRIMARY KEY,
    user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_role       VARCHAR(255),
    resume_text       TEXT NOT NULL,
    job_description   TEXT NOT NULL,
    match_score       INTEGER,
    matched_skills    JSONB,
    missing_skills    JSONB,
    roadmap           JSONB,
    raw_ai_response   JSONB,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analyses_user_id ON analyses(user_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
