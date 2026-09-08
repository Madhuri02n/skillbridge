# SkillBridge AI - fix character encoding on live site
# Run this from PowerShell inside: C:\Users\nmadh\Downloads\skillbridge-ai\skillbridge

New-Item -ItemType Directory -Force -Path "frontend\public" | Out-Null

Write-Host "Writing frontend\index.html..." -ForegroundColor Cyan
@'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
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

Write-Host "Writing frontend\public\_headers..." -ForegroundColor Cyan
@'
/
  Content-Type: text/html; charset=utf-8

/dashboard
  Content-Type: text/html; charset=utf-8

/history
  Content-Type: text/html; charset=utf-8

/login
  Content-Type: text/html; charset=utf-8

/register
  Content-Type: text/html; charset=utf-8
'@ | Set-Content -Path 'frontend\public\_headers' -Encoding UTF8

Write-Host ""
Write-Host "Committing and pushing..." -ForegroundColor Cyan

git add .
git commit -m "Fix character encoding: explicit UTF-8 Content-Type headers"
git push

Write-Host "Done." -ForegroundColor Green
