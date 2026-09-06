import { useEffect, useState } from "react";
import { api } from "../api";
import { useAuth } from "../context/AuthContext";

export default function History() {
  const { token } = useAuth();
  const [items, setItems] = useState([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .history(token)
      .then(setItems)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [token]);

  return (
    <div className="container" style={{ paddingTop: 48, paddingBottom: 80 }}>
      <h1>Your past analyses</h1>
      {loading && <p style={{ color: "var(--text-muted)" }}>Loading...</p>}
      {error && <div className="error-box">{error}</div>}
      {!loading && items.length === 0 && (
        <p style={{ color: "var(--text-muted)" }}>No analyses yet. Run one from the Dashboard.</p>
      )}
      <div style={{ display: "grid", gap: 14, marginTop: 20 }}>
        {items.map((item) => (
          <div key={item.id} className="glass-card" style={{ padding: 20, display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 12 }}>
            <div>
              <div style={{ fontWeight: 700 }}>{item.target_role || "Untitled role"}</div>
              <div style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>
                {new Date(item.created_at).toLocaleString()}
              </div>
            </div>
            <span className="pill pill-matched">{item.match_score}% match</span>
          </div>
        ))}
      </div>
    </div>
  );
}
