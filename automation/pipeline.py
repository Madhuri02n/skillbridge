#!/usr/bin/env python3
"""
SkillBridge AI — Lead -> Qualification -> Personalized Outreach -> Follow-up -> Tracking

Reads docs/leads.csv, scores each lead, generates an AI-personalized cold-email
opener for qualified leads via the Groq API, and writes an outreach queue with
follow-up dates and a status column for response tracking.

Usage:
    export GROQ_API_KEY=your-key
    python3 pipeline.py
"""

import csv
import os
import sys
import json
from datetime import date, timedelta

try:
    import requests
except ImportError:
    print("Missing dependency. Run: pip install requests --break-system-packages")
    sys.exit(1)

LEADS_PATH = os.path.join(os.path.dirname(__file__), "..", "docs", "leads.csv")
OUTPUT_PATH = os.path.join(os.path.dirname(__file__), "outreach_queue.csv")

# Industries considered a strong fit for the product (used in the qualification heuristic).
HIGH_FIT_INDUSTRIES = {
    "Higher Education",
    "Higher Education (Diploma)",
    "Ed-tech / Bootcamp",
    "Ed-tech / Career Platform",
    "Ed-tech / Career Counselling",
    "NGO / Skilling",
}


def qualify(lead: dict) -> int:
    """Simple, auditable 1-5 fit score. Real system would use firmographic/intent data."""
    score = 2
    if lead["Industry"] in HIGH_FIT_INDUSTRIES:
        score += 2
    reason = lead.get("Why They Need It", "")
    if len(reason) > 60:
        score += 1
    return min(score, 5)


def generate_opener(lead: dict) -> str:
    """Calls Groq to draft a 1-paragraph personalized cold-email opener."""
    api_key = os.environ.get("GROQ_API_KEY")
    if not api_key:
        return ("[GROQ_API_KEY not set — sample opener] Hi there, given "
                f"{lead['Company']}'s work in {lead['Industry']}, I thought SkillBridge "
                "AI could help since " + lead["Why They Need It"].strip('"').lower() + ".")

    prompt = (
        "Write one warm, specific, non-generic opening paragraph (2-3 sentences max) for "
        "a cold outreach email to this organization, from a solo builder pitching a free "
        "pilot of an AI resume-vs-job-description skill gap analysis tool called "
        "SkillBridge AI. Reference their specific situation. No greeting, no sign-off, "
        "just the opening paragraph.\n\n"
        f"Company: {lead['Company']}\n"
        f"Industry: {lead['Industry']}\n"
        f"Why they need it: {lead['Why They Need It']}\n"
    )

    resp = requests.post(
        "https://api.groq.com/openai/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={
            "model": "llama-3.3-70b-versatile",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.5,
        },
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    return data["choices"][0]["message"]["content"].strip()


def main():
    if not os.path.exists(LEADS_PATH):
        print(f"Could not find leads file at {LEADS_PATH}")
        sys.exit(1)

    with open(LEADS_PATH, newline="", encoding="utf-8") as f:
        leads = list(csv.DictReader(f))

    today = date.today()
    rows = []
    qualified_count = 0

    for lead in leads:
        score = qualify(lead)
        qualified = score >= 4

        row = {
            "company": lead["Company"],
            "industry": lead["Industry"],
            "decision_maker_role": lead.get("Decision Maker (Role)", ""),
            "fit_score": score,
            "qualified": "yes" if qualified else "no",
            "personalized_opener": "",
            "outreach_date": today.isoformat() if qualified else "",
            "follow_up_1": (today + timedelta(days=3)).isoformat() if qualified else "",
            "follow_up_2": (today + timedelta(days=7)).isoformat() if qualified else "",
            "follow_up_3": (today + timedelta(days=14)).isoformat() if qualified else "",
            "status": "pending" if qualified else "not_qualified",
        }

        if qualified:
            qualified_count += 1
            try:
                row["personalized_opener"] = generate_opener(lead)
            except Exception as e:
                row["personalized_opener"] = f"[AI generation failed: {e}]"

        rows.append(row)

    fieldnames = list(rows[0].keys())
    with open(OUTPUT_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Processed {len(leads)} leads. {qualified_count} qualified (score >= 4).")
    print(f"Output written to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
