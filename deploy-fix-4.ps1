# SkillBridge AI - README update with interview-prep API docs
# Run this from PowerShell inside: C:\Users\nmadh\Downloads\skillbridge-ai\skillbridge

Write-Host "Writing README.md..." -ForegroundColor Cyan
@'
# SkillBridge AI

**Know exactly why you're not getting the interview.**

SkillBridge AI compares a candidate's resume against any job description and returns an
honest fit score, a matched/missing skills breakdown, and a personalized 2-week learning
roadmap — powered by an LLM, backed by Go + PostgreSQL, served through a React UI.

Built as a submission for the RizeOS Founding Engineer take-home assignment.

---

## 1. Problem

Job seekers (especially freshers and career-switchers) apply to dozens of roles without
knowing *why* they're being rejected. Generic resume advice doesn't tell you which specific
skills a specific job actually requires. Career coaches and college placement cells can't
give this kind of personalized feedback at scale.

**Target users:** individual job seekers, bootcamp/college placement cells, career coaches.

**Why they'd pay:** a placement cell paying ₹X/student/month replaces hours of manual
resume review; individual users pay for clarity and a concrete action plan instead of
guessing.

**Differentiation:** most resume tools optimize keyword-stuffing. SkillBridge is honest —
it tells you what you're missing and gives you a plan to close the gap, not just a score
to feel good about.

**Future improvements:** resume parsing from PDF/DOCX upload, JD scraping from a pasted
job URL, tracking roadmap progress over time, employer-side dashboard for bulk candidate
screening, integration with LinkedIn Learning / Coursera APIs for real course links.

---

## 2. Architecture

```
┌─────────────┐      HTTPS       ┌──────────────┐      SQL       ┌──────────────┐
│   React     │ ───────────────▶ │   Go API     │ ─────────────▶ │  PostgreSQL   │
│  (Vercel)   │ ◀─────────────── │  (Render)    │ ◀───────────── │  (Render)     │
└─────────────┘      JSON        └──────┬───────┘                └──────────────┘
                                         │ HTTPS
                                         ▼
                                 ┌───────────────┐
                                 │  Groq LLM API │
                                 │ (llama-3.3-70b)│
                                 └───────────────┘
```

- **Frontend:** React 19 + Vite, React Router, plain CSS (glassmorphism / gradient theme,
  no framework lock-in). Stores JWT in `sessionStorage`.
- **Backend:** Go, [chi](https://github.com/go-chi/chi) router, JWT auth (bcrypt-hashed
  passwords), pgx for PostgreSQL access.
- **Database:** PostgreSQL — `users` and `analyses` tables (see `backend/db/schema.sql`).
- **AI:** [Groq](https://groq.com) OpenAI-compatible chat completions API
  (`llama-3.3-70b-versatile`, free tier) — chosen for speed and zero cost, easily swappable
  for any other LLM provider via `backend/handlers/analyze.go`.

## 3. Tech stack

| Layer     | Choice                                   |
|-----------|-------------------------------------------|
| Frontend  | React, Vite, react-router-dom              |
| Backend   | Go, chi, go-chi/cors, golang-jwt, pgx/v5   |
| Database  | PostgreSQL                                 |
| AI        | Groq API (Llama 3.3 70B)                   |
| Hosting   | Render (API + Postgres, free tier), Vercel (frontend, free tier) |
| Auth      | JWT (HS256), bcrypt password hashing       |

## 4. API reference

Base URL: `https://<your-render-service>.onrender.com`

| Method | Path                 | Auth | Description                              |
|--------|----------------------|------|-------------------------------------------|
| GET    | `/api/health`         | No   | Health check                              |
| POST   | `/api/auth/register`  | No   | `{ name, email, password }` → `{ token, user }` |
| POST   | `/api/auth/login`     | No   | `{ email, password }` → `{ token, user }` |
| POST   | `/api/analyze`        | Yes  | `{ target_role, resume_text, job_description }` → analysis result |
| GET    | `/api/history`        | Yes  | Returns the authenticated user's past analyses |
| POST   | `/api/interview-prep` | Yes  | `{ target_role, resume_text, job_description, missing_skills }` → technical, gap-based, and behavioral interview questions |

Auth uses `Authorization: Bearer <token>`.

**Example — analyze:**
```bash
curl -X POST https://your-api.onrender.com/api/analyze \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "target_role": "Backend Engineer",
    "resume_text": "...",
    "job_description": "..."
  }'
```

Response:
```json
{
  "id": 1,
  "target_role": "Backend Engineer",
  "match_score": 68,
  "matched_skills": ["Go", "REST APIs", "PostgreSQL"],
  "partial_skills": ["Docker"],
  "missing_skills": ["Kubernetes", "gRPC"],
  "summary": "Strong backend fundamentals, missing container orchestration experience.",
  "roadmap": [
    { "week": 1, "focus": "Containers & orchestration basics", "skills": ["Docker", "Kubernetes"], "resources": ["..."] },
    { "week": 2, "focus": "Service-to-service communication", "skills": ["gRPC"], "resources": ["..."] }
  ]
}
```

**Example — interview prep:**
```bash
curl -X POST https://your-api.onrender.com/api/interview-prep \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "target_role": "Backend Engineer",
    "resume_text": "...",
    "job_description": "...",
    "missing_skills": ["Kubernetes", "gRPC"]
  }'
```

Response:
```json
{
  "technical_questions": ["..."],
  "gap_questions": [
    { "question": "How would you design a gRPC service?", "why_asked": "gRPC is required by the job description but not evidenced in your resume." }
  ],
  "behavioral_questions": ["..."]
}
```

## 5. Database schema

See `backend/db/schema.sql`. Two tables: `users` (auth) and `analyses` (stores each
resume/JD pair, the AI's structured response including matched/partial/missing skills,
the roadmap, and a timestamp — JSONB columns throughout for flexibility).

## 6. Local setup

### Prerequisites
- Go 1.21+
- Node.js 18+
- A PostgreSQL database (local, or a free one from [Render](https://render.com) / [Neon](https://neon.tech) / [Supabase](https://supabase.com))
- A free [Groq API key](https://console.groq.com/keys)

### Backend
```bash
cd backend
cp .env.example .env   # fill in DATABASE_URL, JWT_SECRET, GROQ_API_KEY
psql "$DATABASE_URL" -f db/schema.sql   # create tables
export $(cat .env | xargs)              # or use a tool like direnv
go run .
```
API runs on `http://localhost:8080`.

### Frontend
```bash
cd frontend
cp .env.example .env   # set VITE_API_URL=http://localhost:8080
npm install
npm run dev
```
App runs on `http://localhost:5173`.

## 7. Deployment (free tier)

### Backend + Database → Render
1. Push this repo to GitHub.
2. On [Render](https://render.com), click **New → Blueprint**, point it at your repo. It
   will read `render.yaml` and provision the Go web service + free Postgres database
   automatically.
3. Add your `GROQ_API_KEY` in the service's Environment tab (marked `sync: false` in the
   blueprint, so it must be set manually for security).
4. After the first deploy, run the schema once:
   ```bash
   psql "$DATABASE_URL_FROM_RENDER" -f backend/db/schema.sql
   ```
   (Render's Postgres dashboard gives you a connection string and a built-in shell.)

### Frontend → Vercel
1. Import the repo on [Vercel](https://vercel.com), set the project root to `frontend/`.
2. Framework preset: Vite.
3. Add environment variable `VITE_API_URL` = your Render backend URL
   (e.g. `https://skillbridge-api.onrender.com`).
4. Deploy.

Render's free web services sleep after inactivity — the first request after idle may take
~30-50 seconds to wake up. This is expected on the free tier.

## 8. Repo structure

```
skillbridge/
├── backend/
│   ├── main.go
│   ├── db/            # connection + schema.sql
│   ├── models/        # request/response structs
│   ├── handlers/       # auth, analyze, history, health
│   └── middleware/     # JWT auth
├── frontend/
│   └── src/
│       ├── pages/       # Landing, Login, Register, Dashboard, History
│       ├── components/  # Navbar
│       ├── context/     # AuthContext
│       └── api.js
├── render.yaml
└── docs/                # strategy doc, lead sheet, marketing assets (see below)
```

## 9. Business & marketing docs

See the `docs/` folder for:
- `product-strategy.md` — problem, target users, differentiation, roadmap
- `leads.csv` — 30-50 target customers with outreach angle
- `marketing-plan.md` — positioning, landing copy, social posts, outreach messages
- `automation-workflow.md` — Lead → Qualify → Outreach → Follow-up → Track demo
'@ | Set-Content -Path 'README.md' -Encoding UTF8

Write-Host ""
Write-Host "Committing and pushing..." -ForegroundColor Cyan

git add .
git commit -m "Update README with interview-prep API docs"
git push

Write-Host "Done." -ForegroundColor Green
