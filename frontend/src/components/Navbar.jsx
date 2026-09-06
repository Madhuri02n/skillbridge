import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

export default function Navbar() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  return (
    <div className="navbar">
      <div className="container navbar-inner">
        <Link to="/" className="logo">
          Skill<span className="gradient-text">Bridge</span> AI
        </Link>
        <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
          {user ? (
            <>
              <Link to="/dashboard" className="btn btn-ghost" style={{ padding: "8px 18px" }}>
                Dashboard
              </Link>
              <Link to="/history" className="btn btn-ghost" style={{ padding: "8px 18px" }}>
                History
              </Link>
              <button
                className="btn btn-ghost"
                style={{ padding: "8px 18px" }}
                onClick={() => {
                  logout();
                  navigate("/");
                }}
              >
                Log out
              </button>
            </>
          ) : (
            <>
              <Link to="/login" className="btn btn-ghost" style={{ padding: "8px 18px" }}>
                Log in
              </Link>
              <Link to="/register" className="btn btn-primary" style={{ padding: "8px 20px" }}>
                Get started
              </Link>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
