
# SkillBridge AI

**Know exactly why you're not getting the interview.**

SkillBridge AI compares a candidate's resume against any job description and returns an
honest fit score, a matched/partial/missing skills breakdown, a personalized 2-week
learning roadmap, and AI-generated interview preparation — powered by an LLM, backed by
Go + PostgreSQL, served through a React UI.

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
it tells you what you're missing (not just matched/missing, but *partial* matches too),
gives you a plan to close the gap, and preps you for the actual interview questions that
gap is likely to produce.

**Future improvements:** JD scraping from a pasted job URL, tracking roadmap progress over
time and re-scoring, employer-side dashboard for bulk candidate screening, integration
with real course catalogs (Coursera, freeCodeCamp) for clickable verified resource links,
ATS-readiness scoring.

---

## 2. Features

- **Resume input** — paste text, or upload a PDF (text extracted client-side)
- **"Try with sample data"** — instant demo without needing real resume/JD text
- **AI skill-gap analysis** — match score (animated reveal), matched / partial / missing
  skills breakdown, visual skill-distribution bar, honest AI summary
- **Personalized 2-week learning roadmap** — weekly focus, specific skills, real resources
- **AI interview preparation** — technical questions (tied to the actual JD), gap-based
  questions with a "why this is asked" explanation, behavioral questions
- **Auth** — register/login, JWT, bcrypt password hashing, protected routes
- **History** — every past analysis saved; click any entry to expand the full breakdown
  and roadmap, not just the score
- **Futuristic, fully responsive UI** — glassmorphism cards, Space Grotesk + Inter
  typography, smooth animations

## 3. Architecture

```
┌─────────────┐      HTTPS       ┌──────────────┐      SQL       ┌──────────────┐
│   React     │ ───────────────▶ │   Go API     │ ─────────────▶ │  PostgreSQL   │
│  (Render)   │ ◀─────────────── │  (Render)    │ ◀───────────── │  (Render)     │
└─────────────┘      JSON        └──────┬───────┘                └──────────────┘
                                         │ HTTPS
                                         ▼
                                 ┌───────────────┐
                                 │  Groq LLM API │
                                 │(openai/gpt-oss│
                                 │     -120b)    │
                                 └───────────────┘
```

- **Frontend:** React 19 + Vite, React Router, plain CSS (glassmorphism / gradient theme,
  no framework lock-in), pdfjs-dist for client-side PDF text extraction. Stores JWT in
  `sessionStorage`.
- **Backend:** Go, [chi](https://github.com/go-chi/chi) router, JWT auth (bcrypt-hashed
  passwords), pgx for PostgreSQL access. Database schema auto-creates/migrates on startup
  — no manual SQL required for a fresh deploy.
- **Database:** PostgreSQL — `users` and `analyses` tables (see `backend/db/schema.sql`).
- **AI:** [Groq](https://groq.com) OpenAI-compatible chat completions API
  (`openai/gpt-oss-120b`, free tier) — chosen for speed and zero cost, easily swappable
  for any other LLM provider via `backend/handlers/analyze.go` and `interview.go`.

## 4. Tech stack

| Layer     | Choice                                   |
|-----------|-------------------------------------------|
| Frontend  | React, Vite, react-router-dom, pdfjs-dist  |
| Backend   | Go, chi, go-chi/cors, golang-jwt, pgx/v5, bcrypt |
| Database  | PostgreSQL                                 |
| AI        | Groq API (`openai/gpt-oss-120b`)           |
| Hosting   | Render (API + Postgres + static frontend, free tier) |
| Auth      | JWT (HS256), bcrypt password hashing       |

## 5. API reference

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

## 6. Database schema

See `backend/db/schema.sql`. Two tables: `users` (auth) and `analyses` (stores each
resume/JD pair, the AI's structured response including matched/partial/missing skills and
the roadmap, and a timestamp — JSONB columns throughout for flexibility). The backend
(`backend/db/db.go`) also auto-creates and migrates these tables on every startup, so a
fresh Render deploy needs no manual SQL step.

## 7. Local setup

### Prerequisites
- Go 1.21+
- Node.js 18+
- A PostgreSQL database (local, or a free one from [Render](https://render.com) / [Neon](https://neon.tech) / [Supabase](https://supabase.com))
- A free [Groq API key](https://console.groq.com/keys)

### Backend
```bash
cd backend
cp .env.example .env   # fill in DATABASE_URL, JWT_SECRET, GROQ_API_KEY
export $(cat .env | xargs)   # or use a tool like direnv
go run .
```
Tables are created automatically on startup. API runs on `http://localhost:8080`.

### Frontend
```bash
cd frontend
cp .env.example .env   # set VITE_API_URL=http://localhost:8080
npm install
npm run dev
```
App runs on `http://localhost:5173`.

## 8. Deployment (free tier, all on Render)

### Backend + Database
1. Push this repo to GitHub.
2. On [Render](https://render.com), click **New → Blueprint**, point it at your repo. It
   reads `render.yaml` and provisions the Go web service + free Postgres database
   automatically.
3. Add your `GROQ_API_KEY` in the service's Environment tab (marked `sync: false` in the
   blueprint, so it must be set manually for security).
4. Tables are created automatically on first startup — no manual SQL needed.

### Frontend
1. On Render, click **New → Static Site**, point it at the same repo.
2. Root directory: `frontend`. Build command: `npm install && npm run build`. Publish
   directory: `dist`.
3. Add environment variable `VITE_API_URL` = your backend's Render URL
   (e.g. `https://skillbridge-api.onrender.com`).
4. Deploy.

Render's free web services sleep after inactivity — the first request after idle may take
~30-50 seconds to wake up. This is expected on the free tier.

## 9. Repo structure

```
skillbridge/
├── backend/
│   ├── main.go
│   ├── db/              # connection + auto-migrating schema + schema.sql
│   ├── models/          # request/response structs
│   ├── handlers/         # auth, analyze, interview, history, health
│   └── middleware/       # JWT auth
├── frontend/
│   ├── public/_headers   # explicit UTF-8 content-type headers
│   └── src/
│       ├── pages/         # Landing, Login, Register, Dashboard, History
│       ├── components/    # Navbar
│       ├── context/       # AuthContext
│       ├── lib/           # pdf.js (client-side PDF text extraction)
│       └── api.js
├── render.yaml
└── docs/                  # strategy doc, lead sheet, marketing assets (see below)
```

## 10. Business & marketing docs

See the `docs/` folder for:
- `product-strategy.md` — problem, target users, differentiation, roadmap
- `leads.csv` — 40 target customers with outreach angle
- `marketing-plan.md` — positioning, landing copy, social posts, outreach messages
- `automation-workflow.md` + `automation/pipeline.py` — a working, tested
  Lead → Qualify → Personalized Outreach → Follow-up → Track script
'@ | Set-Content -Path 'README.md' -Encoding UTF8

Write-Host ""
Write-Host "Committing and pushing..." -ForegroundColor Cyan

git add .
git commit -m "Final README update: full feature list, correct model, deployment steps"
git push

Write-Host "Done." -ForegroundColor Green
