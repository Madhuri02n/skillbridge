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
