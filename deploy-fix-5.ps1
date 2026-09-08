# SkillBridge AI - proper font pairing (Space Grotesk + Inter)
# Run this from PowerShell inside: C:\Users\nmadh\Downloads\skillbridge-ai\skillbridge

Write-Host "Writing frontend\index.html..." -ForegroundColor Cyan
@'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>SkillBridge AI — Know your skill gap</title>
    <meta name="description" content="Paste your resume and a job description. Get an AI-powered fit score, skill gap analysis, and a 2-week roadmap." />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700;800&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet" />
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
'@ | Set-Content -Path 'frontend\index.html' -Encoding UTF8

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

h1, h2, h3, .logo {
  font-family: 'Space Grotesk', 'Inter', system-ui, sans-serif;
  letter-spacing: -0.01em;
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
Write-Host "Committing and pushing..." -ForegroundColor Cyan

git add .
git commit -m "Add proper font pairing: Space Grotesk headings + Inter body"
git push

Write-Host "Done." -ForegroundColor Green
