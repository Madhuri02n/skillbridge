import { useState } from "react";
import { api } from "../api";
import { useAuth } from "../context/AuthContext";

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
      <h1 style={{ marginBottom: 6 }}>Analyze a role</h1>
      <p style={{ color: "var(--text-muted)", marginTop: 0 }}>
        Paste your resume and the job description you're targeting.
      </p>

      <form onSubmit={handleAnalyze} className="glass-card" style={{ padding: 28, marginTop: 24, display: "grid", gap: 18 }}>
        <div>
          <label>Target role (optional)</label>
          <input value={targetRole} onChange={(e) => setTargetRole(e.target.value)} placeholder="e.g. Backend Engineer" />
        </div>
        <div className="grid-2" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 18 }}>
          <div>
            <label>Your resume</label>
            <textarea
              required
              rows={12}
              value={resumeText}
              onChange={(e) => setResumeText(e.target.value)}
              placeholder="Paste your resume text here..."
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
