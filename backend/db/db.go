package db

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

var Pool *pgxpool.Pool

// Connect initializes the global Postgres connection pool using DATABASE_URL.
func Connect() error {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		return fmt.Errorf("DATABASE_URL environment variable is not set")
	}

	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		return fmt.Errorf("unable to create connection pool: %w", err)
	}

	if err := pool.Ping(context.Background()); err != nil {
		return fmt.Errorf("unable to ping database: %w", err)
	}

	Pool = pool

	if err := createTables(); err != nil {
		pool.Close()
		return fmt.Errorf("unable to create database tables: %w", err)
	}

	return nil
}

func createTables() error {
	ctx := context.Background()

	schema := `
	CREATE TABLE IF NOT EXISTS users (
		id SERIAL PRIMARY KEY,
		name VARCHAR(150) NOT NULL,
		email VARCHAR(255) UNIQUE NOT NULL,
		password_hash TEXT NOT NULL,
		created_at TIMESTAMPTZ NOT NULL DEFAULT now()
	);

	CREATE TABLE IF NOT EXISTS analyses (
		id SERIAL PRIMARY KEY,
		user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		target_role VARCHAR(255),
		resume_text TEXT NOT NULL,
		job_description TEXT NOT NULL,
		match_score INTEGER,
		matched_skills JSONB,
		partial_skills JSONB,
		missing_skills JSONB,
		roadmap JSONB,
		raw_ai_response JSONB,
		created_at TIMESTAMPTZ NOT NULL DEFAULT now()
	);

	ALTER TABLE analyses ADD COLUMN IF NOT EXISTS partial_skills JSONB;

	CREATE INDEX IF NOT EXISTS idx_analyses_user_id
	ON analyses(user_id);

	CREATE INDEX IF NOT EXISTS idx_users_email
	ON users(email);
	`

	_, err := Pool.Exec(ctx, schema)
	return err
}
