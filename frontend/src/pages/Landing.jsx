import { Link } from "react-router-dom";

const FEATURES = [
  {
    title: "Paste, don't guess",
    body: "Drop in your resume and a job description. No forms, no fields to fill by hand.",
  },
  {
    title: "AI skill-gap scoring",
    body: "Get an honest match score plus exactly which skills you already have and which are missing.",
  },
  {
    title: "2-week roadmap",
    body: "A specific, realistic plan with resources you can start today, not generic advice.",
  },
];

export default function Landing() {
  return (
    <div>
      <section style={{ padding: "90px 0 60px" }}>
        <div className="container" style={{ textAlign: "center" }}>
          <div className="pill pill-matched" style={{ marginBottom: 24 }}>
            Built for job seekers who are tired of guessing
          </div>
          <h1 style={{ fontSize: "3.2rem", lineHeight: 1.1, margin: "0 0 20px", fontWeight: 800 }}>
            Know exactly why you're<br />
            <span className="gradient-text">not getting the interview.</span>
          </h1>
          <p style={{ color: "var(--text-muted)", fontSize: "1.15rem", maxWidth: 620, margin: "0 auto 36px" }}>
            SkillBridge AI compares your resume against any job description in seconds —
            scoring your fit, naming your gaps, and handing you a 2-week roadmap to close them.
          </p>
          <div style={{ display: "flex", gap: 14, justifyContent: "center" }}>
            <Link to="/register" className="btn btn-primary">Analyze my resume — free</Link>
            <Link to="/login" className="btn btn-ghost">I already have an account</Link>
          </div>
        </div>
      </section>

      <section className="container" style={{ padding: "40px 0 100px" }}>
        <div className="grid-2" style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 20 }}>
          {FEATURES.map((f) => (
            <div key={f.title} className="glass-card fade-in" style={{ padding: 28 }}>
              <h3 style={{ margin: "0 0 10px" }}>{f.title}</h3>
              <p style={{ color: "var(--text-muted)", margin: 0, lineHeight: 1.6 }}>{f.body}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="container" style={{ paddingBottom: 100 }}>
        <div className="glass-card" style={{ padding: 40, textAlign: "center" }}>
          <h2 style={{ marginTop: 0 }}>Placement cells & career coaches</h2>
          <p style={{ color: "var(--text-muted)", maxWidth: 600, margin: "0 auto 20px" }}>
            Give every student a personal skill-gap report against real job postings —
            at a fraction of the cost of 1:1 mentoring.
          </p>
          <Link to="/register" className="btn btn-primary">Talk to us about bulk access</Link>
        </div>
      </section>
    </div>
  );
}
