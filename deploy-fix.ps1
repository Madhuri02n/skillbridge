# SkillBridge AI - one-shot fix script
# Run this from PowerShell inside: C:\Users\nmadh\Downloads\skillbridge-ai\skillbridge

New-Item -ItemType Directory -Force -Path "frontend\src\lib" | Out-Null

Write-Host "Writing backend\handlers\analyze.go..." -ForegroundColor Cyan
@'
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"skillbridge/db"
	"skillbridge/middleware"
	"skillbridge/models"
)

const groqURL = "https://api.groq.com/openai/v1/chat/completions"

// groqChatRequest mirrors the OpenAI-compatible chat completions payload.
type groqChatRequest struct {
	Model    string             `json:"model"`
	Messages []groqChatMessage  `json:"messages"`
	Temperature float64         `json:"temperature"`
}

type groqChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type groqChatResponse struct {
	Choices []struct {
		Message groqChatMessage `json:"message"`
	} `json:"choices"`
}

func callGroqAI(resumeText, jobDescription, targetRole string) (*models.AnalysisResult, map[string]interface{}, error) {
	apiKey := os.Getenv("GROQ_API_KEY")
	if apiKey == "" {
		return nil, nil, fmt.Errorf("GROQ_API_KEY is not configured on the server")
	}

	systemPrompt := `You are an expert technical recruiter and career coach. You compare a candidate's resume against a target job description and respond with STRICT JSON ONLY, no markdown fences, no commentary, matching exactly this schema:
{
  "match_score": <integer 0-100>,
  "matched_skills": [<string>, ...],
  "partial_skills": [<string>, ...],
  "missing_skills": [<string>, ...],
  "summary": "<2-3 sentence honest summary of fit>",
  "roadmap": [
    {"week": 1, "focus": "<short theme>", "skills": [<string>, ...], "resources": [<string, specific course/doc/project idea>, ...]},
    {"week": 2, "focus": "<short theme>", "skills": [<string>, ...], "resources": [<string>, ...]}
  ]
}
"matched_skills" = clearly demonstrated in the resume and required by the JD.
"partial_skills" = adjacent or related experience exists (e.g. used a similar tool, or has foundational knowledge) but not a strong, direct match.
"missing_skills" = required by the JD with no evidence of it in the resume.
Produce exactly 2 roadmap weeks. Be specific and realistic, not generic.`

	userPrompt := fmt.Sprintf("Target role: %s\n\nRESUME:\n%s\n\nJOB DESCRIPTION:\n%s", targetRole, resumeText, jobDescription)

	reqBody := groqChatRequest{
		Model: "llama-3.1-8b-instant",
		Messages: []groqChatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature: 0.3,
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, nil, err
	}

	httpReq, err := http.NewRequest("POST", groqURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, nil, fmt.Errorf("AI provider error (%d): %s", resp.StatusCode, string(respBytes))
	}

	var groqResp groqChatResponse
	if err := json.Unmarshal(respBytes, &groqResp); err != nil {
		return nil, nil, fmt.Errorf("could not parse AI provider response: %w", err)
	}
	if len(groqResp.Choices) == 0 {
		return nil, nil, fmt.Errorf("AI provider returned no choices")
	}

	raw := strings.TrimSpace(groqResp.Choices[0].Message.Content)
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var result models.AnalysisResult
	if err := json.Unmarshal([]byte(raw), &result); err != nil {
		return nil, nil, fmt.Errorf("could not parse AI analysis JSON: %w", err)
	}

	var rawMap map[string]interface{}
	_ = json.Unmarshal([]byte(raw), &rawMap)

	return &result, rawMap, nil
}

func Analyze(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.UserIDFromContext(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req models.AnalyzeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if strings.TrimSpace(req.ResumeText) == "" || strings.TrimSpace(req.JobDescription) == "" {
		writeError(w, http.StatusBadRequest, "resume_text and job_description are required")
		return
	}

	result, rawMap, err := callGroqAI(req.ResumeText, req.JobDescription, req.TargetRole)
	if err != nil {
		writeError(w, http.StatusBadGateway, "AI analysis failed: "+err.Error())
		return
	}

	matchedJSON, _ := json.Marshal(result.MatchedSkills)
	partialJSON, _ := json.Marshal(result.PartialSkills)
	missingJSON, _ := json.Marshal(result.MissingSkills)
	roadmapJSON, _ := json.Marshal(result.Roadmap)
	rawJSON, _ := json.Marshal(rawMap)

	err = db.Pool.QueryRow(context.Background(),
		`INSERT INTO analyses (user_id, target_role, resume_text, job_description, match_score, matched_skills, partial_skills, missing_skills, roadmap, raw_ai_response)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		 RETURNING id, created_at`,
		userID, req.TargetRole, req.ResumeText, req.JobDescription, result.MatchScore, matchedJSON, partialJSON, missingJSON, roadmapJSON, rawJSON,
	).Scan(&result.ID, &result.CreatedAt)

	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to save analysis: "+err.Error())
		return
	}

	result.TargetRole = req.TargetRole
	writeJSON(w, http.StatusOK, result)
}

func History(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.UserIDFromContext(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	rows, err := db.Pool.Query(context.Background(),
		`SELECT id, target_role, match_score, matched_skills, partial_skills, missing_skills, roadmap, created_at
		 FROM analyses WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`,
		userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to fetch history")
		return
	}
	defer rows.Close()

	results := []models.AnalysisResult{}
	for rows.Next() {
		var a models.AnalysisResult
		var matchedJSON, partialJSON, missingJSON, roadmapJSON []byte
		if err := rows.Scan(&a.ID, &a.TargetRole, &a.MatchScore, &matchedJSON, &partialJSON, &missingJSON, &roadmapJSON, &a.CreatedAt); err != nil {
			continue
		}
		_ = json.Unmarshal(matchedJSON, &a.MatchedSkills)
		_ = json.Unmarshal(partialJSON, &a.PartialSkills)
		_ = json.Unmarshal(missingJSON, &a.MissingSkills)
		_ = json.Unmarshal(roadmapJSON, &a.Roadmap)
		results = append(results, a)
	}

	writeJSON(w, http.StatusOK, results)
}
'@ | Set-Content -Path 'backend\handlers\analyze.go' -Encoding UTF8

Write-Host "Writing backend\models\models.go..." -ForegroundColor Cyan
@'
package models

import "time"

type User struct {
	ID           int       `json:"id"`
	Name         string    `json:"name"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"created_at"`
}

type RegisterRequest struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type AuthResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

type AnalyzeRequest struct {
	TargetRole      string `json:"target_role"`
	ResumeText      string `json:"resume_text"`
	JobDescription  string `json:"job_description"`
}

type RoadmapItem struct {
	Week      int      `json:"week"`
	Focus     string   `json:"focus"`
	Skills    []string `json:"skills"`
	Resources []string `json:"resources"`
}

type AnalysisResult struct {
	ID             int           `json:"id"`
	TargetRole     string        `json:"target_role"`
	MatchScore     int           `json:"match_score"`
	MatchedSkills  []string      `json:"matched_skills"`
	PartialSkills  []string      `json:"partial_skills"`
	MissingSkills  []string      `json:"missing_skills"`
	Summary        string        `json:"summary"`
	Roadmap        []RoadmapItem `json:"roadmap"`
	CreatedAt      time.Time     `json:"created_at,omitempty"`
}
'@ | Set-Content -Path 'backend\models\models.go' -Encoding UTF8

Write-Host "Writing backend\db\db.go..." -ForegroundColor Cyan
@'
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
'@ | Set-Content -Path 'backend\db\db.go' -Encoding UTF8

Write-Host "Writing frontend\src\pages\Dashboard.jsx..." -ForegroundColor Cyan
@'
import { useState, useRef, useEffect } from "react";
import { api } from "../api";
import { useAuth } from "../context/AuthContext";
import { extractTextFromPdf } from "../lib/pdf";

const SAMPLE_RESUME = `Madhuri N — B.Tech Computer Science, JNTUH Hyderabad (CGPA 8.85)
Skills: Java, Spring Boot, Python, React.js, Node.js, Express.js, MongoDB, MySQL, Git
Projects:
- Inventory Management System — Java, Spring Boot, JPA, MySQL, React.js. Built REST API with 10 endpoints, JWT auth, dashboard analytics.
- PrediCare — Python, Flask, Random Forest, Gemini API. ML disease prediction app, 83% accuracy.
- WordNook — MERN stack social blogging platform with JWT auth, likes, comments.
Achievements: LeetCode Knight (300+ problems), Goldman Sachs India Catalyst Program mentee.`;

const SAMPLE_JD = `Software Developer Intern — Backend Focus
We're looking for a backend-leaning full-stack developer intern comfortable with:
- Go or Java for REST API development
- PostgreSQL or MySQL, schema design
- Docker and basic Kubernetes concepts
- CI/CD pipelines (GitHub Actions)
- Experience deploying to cloud platforms (Render, AWS, or GCP)
- gRPC or microservices experience is a plus`;

function ScoreRing({ score = 0 }) {
  const [displayScore, setDisplayScore] = useState(0);

  useEffect(() => {
    setDisplayScore(0);
    const duration = 900;
    const start = performance.now();

    let frameId;
    function tick(now) {
      const progress = Math.min((now - start) / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3); // ease-out cubic
      setDisplayScore(Math.round(eased * score));
      if (progress < 1) frameId = requestAnimationFrame(tick);
    }
    frameId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frameId);
  }, [score]);

  const color = score >= 70 ? "var(--success)" : score >= 40 ? "#fbbf24" : "var(--danger)";
  const bg = `conic-gradient(${color} ${displayScore * 3.6}deg, rgba(255,255,255,0.08) 0deg)`;
  return (
    <div className="score-ring" style={{ background: bg }}>
      <div
        style={{
          position: "absolute",
          inset: 8,
          borderRadius: "50%",
          background: "var(--bg-deep)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexDirection: "column",
        }}
      >
        <span>{displayScore}%</span>
        <span style={{ fontSize: "0.7rem", color: "var(--text-muted)", fontWeight: 500 }}>match</span>
      </div>
    </div>
  );
}

export default function Dashboard() {
  const { token } = useAuth();
  const [targetRole, setTargetRole] = useState("");
  const [resumeText, setResumeText] = useState("");
  const [jobDescription, setJobDescription] = useState("");
  const [result, setResult] = useState(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [pdfLoading, setPdfLoading] = useState(false);
  const fileInputRef = useRef(null);

  async function handlePdfUpload(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setError("");
    setPdfLoading(true);
    try {
      const text = await extractTextFromPdf(file);
      if (!text || text.length < 20) {
        setError("Couldn't read text from that PDF — it may be a scanned image. Try pasting the text instead.");
      } else {
        setResumeText(text);
      }
    } catch (err) {
      setError("Failed to read PDF: " + err.message);
    } finally {
      setPdfLoading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  function loadSample() {
    setTargetRole("Backend Developer Intern");
    setResumeText(SAMPLE_RESUME);
    setJobDescription(SAMPLE_JD);
    setError("");
  }

  async function handleAnalyze(e) {
    e.preventDefault();
    setError("");
    setResult(null);
    setLoading(true);
    try {
      const data = await api.analyze({ target_role: targetRole, resume_text: resumeText, job_description: jobDescription }, token);
      setResult(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="container" style={{ paddingTop: 48, paddingBottom: 80 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: 12 }}>
        <div>
          <h1 style={{ marginBottom: 6 }}>Analyze a role</h1>
          <p style={{ color: "var(--text-muted)", marginTop: 0 }}>
            Upload or paste your resume, then the job description you're targeting.
          </p>
        </div>
        <button type="button" className="btn btn-ghost" onClick={loadSample} style={{ padding: "8px 18px" }}>
          Try with sample data
        </button>
      </div>

      <form onSubmit={handleAnalyze} className="glass-card" style={{ padding: 28, marginTop: 24, display: "grid", gap: 18 }}>
        <div>
          <label>Target role (optional)</label>
          <input value={targetRole} onChange={(e) => setTargetRole(e.target.value)} placeholder="e.g. Backend Engineer" />
        </div>
        <div className="grid-2" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 18 }}>
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
              <label style={{ marginBottom: 0 }}>Your resume</label>
              <label
                htmlFor="pdf-upload"
                className="btn btn-ghost"
                style={{ padding: "4px 12px", fontSize: "0.78rem", cursor: "pointer" }}
              >
                {pdfLoading ? <span className="spinner" /> : "Upload PDF"}
              </label>
              <input
                id="pdf-upload"
                ref={fileInputRef}
                type="file"
                accept="application/pdf"
                onChange={handlePdfUpload}
                style={{ display: "none" }}
              />
            </div>
            <textarea
              required
              rows={12}
              value={resumeText}
              onChange={(e) => setResumeText(e.target.value)}
              placeholder="Paste your resume text here, or upload a PDF above..."
            />
          </div>
          <div>
            <label>Job description</label>
            <textarea
              required
              rows={12}
              value={jobDescription}
              onChange={(e) => setJobDescription(e.target.value)}
              placeholder="Paste the job description here..."
            />
          </div>
        </div>
        {error && <div className="error-box">{error}</div>}
        <button className="btn btn-primary" type="submit" disabled={loading} style={{ justifySelf: "start" }}>
          {loading && <span className="spinner" />} {loading ? "Analyzing..." : "Analyze fit"}
        </button>
      </form>

      {result && (
        <div className="fade-in" style={{ marginTop: 32, display: "grid", gap: 20 }}>
          <div className="glass-card" style={{ padding: 28, display: "flex", gap: 28, alignItems: "center", flexWrap: "wrap" }}>
            <ScoreRing score={result.match_score} />
            <div style={{ flex: 1, minWidth: 240 }}>
              <h3 style={{ marginTop: 0 }}>Summary</h3>
              <p style={{ color: "var(--text-muted)", lineHeight: 1.6 }}>{result.summary}</p>
            </div>
          </div>

          <div className="glass-card" style={{ padding: 28 }}>
            <h3 style={{ marginTop: 0 }}>Skills breakdown</h3>
            <div style={{ marginBottom: 16 }}>
              <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>✓ MATCHED</div>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                {result.matched_skills?.map((s) => (
                  <span key={s} className="pill pill-matched">{s}</span>
                ))}
              </div>
            </div>
            {result.partial_skills?.length > 0 && (
              <div style={{ marginBottom: 16 }}>
                <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>⚠ PARTIAL</div>
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                  {result.partial_skills?.map((s) => (
                    <span key={s} className="pill pill-partial">{s}</span>
                  ))}
                </div>
              </div>
            )}
            <div>
              <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>✗ MISSING</div>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                {result.missing_skills?.map((s) => (
                  <span key={s} className="pill pill-missing">{s}</span>
                ))}
              </div>
            </div>
          </div>

          <div className="glass-card" style={{ padding: 28 }}>
            <h3 style={{ marginTop: 0 }}>Your 2-week roadmap</h3>
            <div style={{ display: "grid", gap: 16 }}>
              {result.roadmap?.map((week) => (
                <div key={week.week} style={{ borderLeft: "3px solid var(--accent-2)", paddingLeft: 16 }}>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Week {week.week} — {week.focus}</div>
                  <div style={{ color: "var(--text-muted)", fontSize: "0.9rem", marginBottom: 6 }}>
                    Skills: {week.skills?.join(", ")}
                  </div>
                  <ul style={{ margin: 0, paddingLeft: 18, color: "var(--text-muted)" }}>
                    {week.resources?.map((r, i) => <li key={i}>{r}</li>)}
                  </ul>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
'@ | Set-Content -Path 'frontend\src\pages\Dashboard.jsx' -Encoding UTF8

Write-Host "Writing frontend\src\lib\pdf.js..." -ForegroundColor Cyan
@'
import * as pdfjsLib from "pdfjs-dist";

pdfjsLib.GlobalWorkerOptions.workerSrc = `https://cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjsLib.version}/pdf.worker.min.mjs`;

/**
 * Extracts plain text from a PDF File object (e.g. from an <input type="file">).
 * Returns a single string with page breaks as double newlines.
 */
export async function extractTextFromPdf(file) {
  const arrayBuffer = await file.arrayBuffer();
  const pdf = await pdfjsLib.getDocument({ data: arrayBuffer }).promise;

  const pageTexts = [];
  for (let pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
    const page = await pdf.getPage(pageNum);
    const content = await page.getTextContent();
    const text = content.items.map((item) => item.str).join(" ");
    pageTexts.push(text);
  }

  return pageTexts.join("\n\n").trim();
}
'@ | Set-Content -Path 'frontend\src\lib\pdf.js' -Encoding UTF8

Write-Host "Writing frontend\src\index.css..." -ForegroundColor Cyan
@'
:root {
  --bg-deep: #05060f;
  --bg-panel: rgba(255, 255, 255, 0.04);
  --border-glow: rgba(124, 92, 255, 0.35);
  --accent-1: #7c5cff;
  --accent-2: #22d3ee;
  --accent-3: #ff5da2;
  --text-primary: #f4f4fb;
  --text-muted: #9aa0b4;
  --success: #34d399;
  --danger: #f87171;
  font-family: 'Inter', 'Segoe UI', system-ui, sans-serif;
}

* { box-sizing: border-box; }

html, body, #root {
  margin: 0;
  min-height: 100%;
  background: radial-gradient(circle at 20% -10%, rgba(124,92,255,0.25), transparent 45%),
              radial-gradient(circle at 90% 10%, rgba(34,211,238,0.18), transparent 40%),
              var(--bg-deep);
  color: var(--text-primary);
}

a { color: inherit; text-decoration: none; }

.container {
  max-width: 1100px;
  margin: 0 auto;
  padding: 0 24px;
}

.glass-card {
  background: var(--bg-panel);
  border: 1px solid var(--border-glow);
  border-radius: 20px;
  backdrop-filter: blur(14px);
  box-shadow: 0 20px 60px rgba(0,0,0,0.35);
}

.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 12px 24px;
  border-radius: 999px;
  border: none;
  font-weight: 600;
  font-size: 0.95rem;
  cursor: pointer;
  transition: transform 0.15s ease, box-shadow 0.15s ease, opacity 0.15s ease;
}

.btn:disabled { opacity: 0.55; cursor: not-allowed; }

.btn-primary {
  background: linear-gradient(135deg, var(--accent-1), var(--accent-2));
  color: #05060f;
  box-shadow: 0 8px 30px rgba(124,92,255,0.35);
}
.btn-primary:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 12px 36px rgba(124,92,255,0.5); }

.btn-ghost {
  background: transparent;
  border: 1px solid var(--border-glow);
  color: var(--text-primary);
}
.btn-ghost:hover { border-color: var(--accent-2); }

input, textarea {
  width: 100%;
  padding: 12px 16px;
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.12);
  background: rgba(255,255,255,0.03);
  color: var(--text-primary);
  font-size: 0.95rem;
  font-family: inherit;
  resize: vertical;
}
input:focus, textarea:focus {
  outline: none;
  border-color: var(--accent-2);
  box-shadow: 0 0 0 3px rgba(34,211,238,0.15);
}

label {
  display: block;
  font-size: 0.85rem;
  color: var(--text-muted);
  margin-bottom: 6px;
  font-weight: 600;
  letter-spacing: 0.02em;
}

.pill {
  display: inline-flex;
  align-items: center;
  padding: 5px 14px;
  border-radius: 999px;
  font-size: 0.8rem;
  font-weight: 600;
}
.pill-matched { background: rgba(52,211,153,0.15); color: var(--success); border: 1px solid rgba(52,211,153,0.3); }
.pill-partial { background: rgba(251,191,36,0.15); color: #fbbf24; border: 1px solid rgba(251,191,36,0.3); }
.pill-missing { background: rgba(248,113,113,0.15); color: var(--danger); border: 1px solid rgba(248,113,113,0.3); }

.gradient-text {
  background: linear-gradient(135deg, var(--accent-1), var(--accent-2), var(--accent-3));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.navbar {
  position: sticky;
  top: 0;
  z-index: 10;
  padding: 18px 0;
  border-bottom: 1px solid rgba(255,255,255,0.06);
  background: rgba(5,6,15,0.75);
  backdrop-filter: blur(10px);
}
.navbar-inner { display: flex; align-items: center; justify-content: space-between; }
.logo { font-weight: 800; font-size: 1.25rem; letter-spacing: -0.02em; }

.error-box {
  background: rgba(248,113,113,0.1);
  border: 1px solid rgba(248,113,113,0.3);
  color: #fca5a5;
  padding: 12px 16px;
  border-radius: 12px;
  font-size: 0.9rem;
}

.score-ring {
  width: 140px;
  height: 140px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 2rem;
  font-weight: 800;
  position: relative;
}

.spinner {
  width: 18px;
  height: 18px;
  border: 2px solid rgba(5,6,15,0.3);
  border-top-color: #05060f;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.fade-in { animation: fadeIn 0.5s ease both; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }

@media (max-width: 640px) {
  .grid-2 { grid-template-columns: 1fr !important; }
}
'@ | Set-Content -Path 'frontend\src\index.css' -Encoding UTF8

Write-Host ""
Write-Host "All files written. Committing and pushing to GitHub..." -ForegroundColor Cyan

git add .
git commit -m "Fix AI model, add partial-skills tier, PDF upload, animated score"
git push

Write-Host ""
Write-Host "Done. Render and Vercel will auto-redeploy in 1-2 minutes." -ForegroundColor Green
Write-Host "Check Render dashboard for skillbridge-api status = Live, then test your site." -ForegroundColor Green
