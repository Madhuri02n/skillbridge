# Automation Demo — Lead → Qualify → Outreach → Follow-up → Track

This demonstrates the automation described in the assignment: a lightweight, AI-assisted
pipeline that takes the lead sheet (`leads.csv`) and turns it into personalized outreach
messages with a follow-up schedule and response tracking — the kind of workflow that
would run for real via a cron job + email API in production.

A working prototype is provided at `automation/pipeline.py`. It is intentionally small
and dependency-light (stdlib only, plus the same Groq API used by the product) so it can
be run and inspected in minutes.

## Pipeline stages

1. **Lead** — reads `docs/leads.csv`.
2. **Qualification** — scores each lead 1-5 on fit using simple rules (industry match +
   presence of a specific "why they need it" reason) — in production this step would use
   firmographic/intent data; here it's a transparent heuristic so it's auditable.
3. **Personalized outreach** — for leads scoring 4-5, calls the Groq AI to generate a
   1-paragraph personalized cold email opener referencing their specific industry and
   pain point (pulled straight from the CSV's "Why They Need It" column).
4. **Follow-up scheduling** — writes a `follow_up_date` (day 3, 7, 14 after first contact)
   into the output.
5. **Response tracking** — the output CSV includes a `status` column
   (`pending` / `replied` / `no_response` / `converted`) that a human (or a future
   inbox-watching automation) updates as replies come in.

## Running it

```bash
cd automation
pip install requests --break-system-packages   # only external dependency
export GROQ_API_KEY=your-key
python3 pipeline.py
```

Output: `automation/outreach_queue.csv` — one row per qualified lead, with a personalized
opener, next follow-up date, and status column ready for tracking.

## Production version

In a real deployment this same logic would run as:
- A scheduled job (cron / Render Cron Job) that re-reads the CRM/lead sheet daily.
- Outreach sent via an email API (e.g. Resend, SendGrid) instead of printed to CSV.
- Replies tracked via a shared inbox webhook or CRM (e.g. a lightweight Airtable/Postgres
  table) updating the `status` column automatically instead of manually.
- A daily digest emailed to the founder summarizing new replies and leads due for
  follow-up that day.
