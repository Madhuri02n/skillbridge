# SkillBridge AI - remaining features update
# Run this from PowerShell inside: C:\Users\nmadh\Downloads\skillbridge-ai\skillbridge

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
		Model: "openai/gpt-oss-120b",
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
};
'@ | Set-Content -Path 'frontend\src\api.js' -Encoding UTF8

Write-Host "Writing frontend\src\pages\History.jsx..." -ForegroundColor Cyan
@'
import { useEffect, useState } from "react";
import { api } from "../api";
import { useAuth } from "../context/AuthContext";

export default function History() {
  const { token } = useAuth();
  const [items, setItems] = useState([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState(null);

  useEffect(() => {
    api
      .history(token)
      .then(setItems)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [token]);

  function toggle(id) {
    setExpandedId((current) => (current === id ? null : id));
  }

  return (
    <div className="container" style={{ paddingTop: 48, paddingBottom: 80 }}>
      <h1>Your past analyses</h1>
      {loading && <p style={{ color: "var(--text-muted)" }}>Loading...</p>}
      {error && <div className="error-box">{error}</div>}
      {!loading && items.length === 0 && (
        <p style={{ color: "var(--text-muted)" }}>No analyses yet. Run one from the Dashboard.</p>
      )}
      <div style={{ display: "grid", gap: 14, marginTop: 20 }}>
        {items.map((item) => {
          const isOpen = expandedId === item.id;
          return (
            <div key={item.id} className="glass-card" style={{ padding: 20 }}>
              <div
                onClick={() => toggle(item.id)}
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  flexWrap: "wrap",
                  gap: 12,
                  cursor: "pointer",
                }}
              >
                <div>
                  <div style={{ fontWeight: 700 }}>{item.target_role || "Untitled role"}</div>
                  <div style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>
                    {new Date(item.created_at).toLocaleString()}
                  </div>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                  <span className="pill pill-matched">{item.match_score}% match</span>
                  <span style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>
                    {isOpen ? "Hide details ▲" : "View details ▼"}
                  </span>
                </div>
              </div>

              {isOpen && (
                <div className="fade-in" style={{ marginTop: 20, paddingTop: 20, borderTop: "1px solid rgba(255,255,255,0.08)" }}>
                  <div style={{ marginBottom: 16 }}>
                    <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>✓ MATCHED</div>
                    <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                      {item.matched_skills?.length
                        ? item.matched_skills.map((s) => <span key={s} className="pill pill-matched">{s}</span>)
                        : <span style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>None recorded</span>}
                    </div>
                  </div>

                  {item.partial_skills?.length > 0 && (
                    <div style={{ marginBottom: 16 }}>
                      <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>⚠ PARTIAL</div>
                      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                        {item.partial_skills.map((s) => <span key={s} className="pill pill-partial">{s}</span>)}
                      </div>
                    </div>
                  )}

                  <div style={{ marginBottom: 20 }}>
                    <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>✗ MISSING</div>
                    <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                      {item.missing_skills?.length
                        ? item.missing_skills.map((s) => <span key={s} className="pill pill-missing">{s}</span>)
                        : <span style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>None recorded</span>}
                    </div>
                  </div>

                  {item.roadmap?.length > 0 && (
                    <div>
                      <div style={{ marginBottom: 10, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>ROADMAP</div>
                      <div style={{ display: "grid", gap: 14 }}>
                        {item.roadmap.map((week) => (
                          <div key={week.week} style={{ borderLeft: "3px solid var(--accent-2)", paddingLeft: 14 }}>
                            <div style={{ fontWeight: 700, marginBottom: 4 }}>Week {week.week} — {week.focus}</div>
                            <ul style={{ margin: 0, paddingLeft: 18, color: "var(--text-muted)", fontSize: "0.9rem" }}>
                              {week.resources?.map((r, i) => <li key={i}>{r}</li>)}
                            </ul>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
'@ | Set-Content -Path 'frontend\src\pages\History.jsx' -Encoding UTF8

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
        </div>
      )}
    </div>
  );
}
'@ | Set-Content -Path 'frontend\src\pages\Dashboard.jsx' -Encoding UTF8

Write-Host ""
Write-Host "All files written. Committing and pushing to GitHub..." -ForegroundColor Cyan

git add .
git commit -m "Add expandable history detail view, skill distribution bar, fix UTF-8 encoding"
git push

Write-Host ""
Write-Host "Done. Render/Vercel will auto-redeploy in 1-2 minutes." -ForegroundColor Green
