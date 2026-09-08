# SkillBridge AI - Interview Preparation feature
# Run this from PowerShell inside: C:\Users\nmadh\Downloads\skillbridge-ai\skillbridge

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

type InterviewPrepRequest struct {
	TargetRole     string   `json:"target_role"`
	ResumeText     string   `json:"resume_text"`
	JobDescription string   `json:"job_description"`
	MissingSkills  []string `json:"missing_skills"`
}

type InterviewPrepResult struct {
	TechnicalQuestions   []string `json:"technical_questions"`
	GapQuestions         []GapQuestion `json:"gap_questions"`
	BehavioralQuestions  []string `json:"behavioral_questions"`
}

type GapQuestion struct {
	Question    string `json:"question"`
	WhyAsked    string `json:"why_asked"`
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

Write-Host "Writing backend\handlers\interview.go..." -ForegroundColor Cyan
@'
package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"skillbridge/middleware"
	"skillbridge/models"
)

func callGroqInterviewPrep(req models.InterviewPrepRequest) (*models.InterviewPrepResult, error) {
	apiKey := os.Getenv("GROQ_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GROQ_API_KEY is not configured on the server")
	}

	systemPrompt := `You are an expert technical interviewer preparing a candidate for a real interview. Respond with STRICT JSON ONLY, no markdown fences, no commentary, matching exactly this schema:
{
  "technical_questions": [<string>, ...],
  "gap_questions": [
    {"question": "<string>", "why_asked": "<one sentence explaining why this question relates to a specific skill gap>"}
  ],
  "behavioral_questions": [<string>, ...]
}
Generate 4-5 technical_questions based on the skills actually required by the job description.
Generate 2-3 gap_questions specifically probing the candidate's weakest/missing areas, each with a short "why_asked" explanation.
Generate 3 standard behavioral_questions relevant to the role level.
Be specific to this resume and job, not generic filler questions.`

	userPrompt := fmt.Sprintf(
		"Target role: %s\n\nRESUME:\n%s\n\nJOB DESCRIPTION:\n%s\n\nKNOWN MISSING SKILLS:\n%s",
		req.TargetRole, req.ResumeText, req.JobDescription, strings.Join(req.MissingSkills, ", "),
	)

	reqBody := groqChatRequest{
		Model: "openai/gpt-oss-120b",
		Messages: []groqChatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature: 0.4,
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	httpReq, err := http.NewRequest("POST", groqURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json; charset=utf-8")
	httpReq.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("AI provider error (%d): %s", resp.StatusCode, string(respBytes))
	}

	var groqResp groqChatResponse
	if err := json.Unmarshal(respBytes, &groqResp); err != nil {
		return nil, fmt.Errorf("could not parse AI provider response: %w", err)
	}
	if len(groqResp.Choices) == 0 {
		return nil, fmt.Errorf("AI provider returned no choices")
	}

	raw := strings.TrimSpace(groqResp.Choices[0].Message.Content)
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var result models.InterviewPrepResult
	if err := json.Unmarshal([]byte(raw), &result); err != nil {
		return nil, fmt.Errorf("could not parse interview prep JSON: %w", err)
	}

	return &result, nil
}

func InterviewPrep(w http.ResponseWriter, r *http.Request) {
	_, ok := middleware.UserIDFromContext(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req models.InterviewPrepRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if strings.TrimSpace(req.ResumeText) == "" || strings.TrimSpace(req.JobDescription) == "" {
		writeError(w, http.StatusBadRequest, "resume_text and job_description are required")
		return
	}

	result, err := callGroqInterviewPrep(req)
	if err != nil {
		writeError(w, http.StatusBadGateway, "Interview prep generation failed: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, result)
}
'@ | Set-Content -Path 'backend\handlers\interview.go' -Encoding UTF8

Write-Host "Writing backend\main.go..." -ForegroundColor Cyan
@'
package main

import (
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"

	"skillbridge/db"
	"skillbridge/handlers"
	"skillbridge/middleware"
)

func main() {
	if err := db.Connect(); err != nil {
		log.Fatalf("database connection failed: %v", err)
	}
	log.Println("connected to database")

	r := chi.NewRouter()
	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		AllowCredentials: false,
		MaxAge:           300,
	}))

	r.Get("/api/health", handlers.Health)
	r.Post("/api/auth/register", handlers.Register)
	r.Post("/api/auth/login", handlers.Login)

	r.Group(func(protected chi.Router) {
		protected.Use(middleware.RequireAuth)
		protected.Post("/api/analyze", handlers.Analyze)
		protected.Get("/api/history", handlers.History)
		protected.Post("/api/interview-prep", handlers.InterviewPrep)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("SkillBridge API listening on :%s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatal(err)
	}
}
'@ | Set-Content -Path 'backend\main.go' -Encoding UTF8

Write-Host "Writing frontend\src\api.js..." -ForegroundColor Cyan
@'
const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:8080";

async function request(path, { method = "GET", body, token } = {}) {
  const headers = { "Content-Type": "application/json; charset=utf-8" };
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_BASE}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  let data;
  try {
    data = await res.json();
  } catch {
    data = null;
  }

  if (!res.ok) {
    throw new Error(data?.error || `Request failed with status ${res.status}`);
  }
  return data;
}

export const api = {
  register: (payload) => request("/api/auth/register", { method: "POST", body: payload }),
  login: (payload) => request("/api/auth/login", { method: "POST", body: payload }),
  analyze: (payload, token) => request("/api/analyze", { method: "POST", body: payload, token }),
  history: (token) => request("/api/history", { token }),
  interviewPrep: (payload, token) => request("/api/interview-prep", { method: "POST", body: payload, token }),
};
'@ | Set-Content -Path 'frontend\src\api.js' -Encoding UTF8

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
  const [prep, setPrep] = useState(null);
  const [prepError, setPrepError] = useState("");
  const [prepLoading, setPrepLoading] = useState(false);
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
    setPrep(null);
    setPrepError("");
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

  async function handlePrepareInterview() {
    setPrepError("");
    setPrepLoading(true);
    try {
      const data = await api.interviewPrep(
        {
          target_role: targetRole,
          resume_text: resumeText,
          job_description: jobDescription,
          missing_skills: result?.missing_skills || [],
        },
        token
      );
      setPrep(data);
    } catch (err) {
      setPrepError(err.message);
    } finally {
      setPrepLoading(false);
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
              {(() => {
                const matched = result.matched_skills?.length || 0;
                const partial = result.partial_skills?.length || 0;
                const missing = result.missing_skills?.length || 0;
                const total = matched + partial + missing || 1;
                return (
                  <div style={{ marginTop: 12 }}>
                    <div style={{ display: "flex", height: 10, borderRadius: 999, overflow: "hidden", background: "rgba(255,255,255,0.06)" }}>
                      <div style={{ width: `${(matched / total) * 100}%`, background: "var(--success)" }} />
                      <div style={{ width: `${(partial / total) * 100}%`, background: "#fbbf24" }} />
                      <div style={{ width: `${(missing / total) * 100}%`, background: "var(--danger)" }} />
                    </div>
                    <div style={{ display: "flex", gap: 16, marginTop: 8, fontSize: "0.78rem", color: "var(--text-muted)" }}>
                      <span>{matched} matched</span>
                      {partial > 0 && <span>{partial} partial</span>}
                      <span>{missing} missing</span>
                    </div>
                  </div>
                );
              })()}
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

          {!prep && (
            <div style={{ textAlign: "center" }}>
              <button className="btn btn-primary" type="button" onClick={handlePrepareInterview} disabled={prepLoading}>
                {prepLoading && <span className="spinner" />} {prepLoading ? "Preparing..." : "🎯 Prepare for Interview"}
              </button>
              {prepError && <div className="error-box" style={{ marginTop: 16 }}>{prepError}</div>}
            </div>
          )}

          {prep && (
            <div className="glass-card fade-in" style={{ padding: 28 }}>
              <h3 style={{ marginTop: 0 }}>🎯 Interview Preparation</h3>

              <div style={{ marginBottom: 20 }}>
                <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>TECHNICAL QUESTIONS</div>
                <ol style={{ margin: 0, paddingLeft: 20, display: "grid", gap: 8 }}>
                  {prep.technical_questions?.map((q, i) => (
                    <li key={i} style={{ color: "var(--text-primary)" }}>{q}</li>
                  ))}
                </ol>
              </div>

              {prep.gap_questions?.length > 0 && (
                <div style={{ marginBottom: 20 }}>
                  <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>QUESTIONS BASED ON YOUR GAPS</div>
                  <div style={{ display: "grid", gap: 12 }}>
                    {prep.gap_questions.map((g, i) => (
                      <div key={i} style={{ borderLeft: "3px solid #fbbf24", paddingLeft: 14 }}>
                        <div style={{ fontWeight: 600 }}>{g.question}</div>
                        <div style={{ color: "var(--text-muted)", fontSize: "0.85rem", marginTop: 2 }}>{g.why_asked}</div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <div>
                <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>BEHAVIORAL QUESTIONS</div>
                <ol style={{ margin: 0, paddingLeft: 20, display: "grid", gap: 8 }}>
                  {prep.behavioral_questions?.map((q, i) => (
                    <li key={i} style={{ color: "var(--text-primary)" }}>{q}</li>
                  ))}
                </ol>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
'@ | Set-Content -Path 'frontend\src\pages\Dashboard.jsx' -Encoding UTF8

Write-Host ""
Write-Host "All files written. Committing and pushing to GitHub..." -ForegroundColor Cyan

git add .
git commit -m "Add AI-powered Interview Preparation feature"
git push

Write-Host ""
Write-Host "Done. Render/Vercel will auto-redeploy in 1-2 minutes." -ForegroundColor Green
