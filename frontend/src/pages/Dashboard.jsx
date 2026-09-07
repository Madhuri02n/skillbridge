import { useState, useRef } from "react";
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
  const color = score >= 70 ? "var(--success)" : score >= 40 ? "#fbbf24" : "var(--danger)";
  const bg = `conic-gradient(${color} ${score * 3.6}deg, rgba(255,255,255,0.08) 0deg)`;
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
        <span>{score}%</span>
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
              <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>MATCHED</div>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                {result.matched_skills?.map((s) => (
                  <span key={s} className="pill pill-matched">{s}</span>
                ))}
              </div>
            </div>
            <div>
              <div style={{ marginBottom: 8, color: "var(--text-muted)", fontSize: "0.85rem", fontWeight: 600 }}>MISSING</div>
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