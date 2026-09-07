package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"skillbridge/db"
	"skillbridge/middleware"
	"skillbridge/models"
)

const groqURL = "https://api.groq.com/openai/v1/chat/completions"

// groqChatRequest mirrors the OpenAI-compatible chat completions payload.
type groqChatRequest struct {
	Model    string             `json:"model"`
	Messages []groqChatMessage  `json:"messages"`
	Temperature float64         `json:"temperature"`
}

type groqChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type groqChatResponse struct {
	Choices []struct {
		Message groqChatMessage `json:"message"`
	} `json:"choices"`
}

func callGroqAI(resumeText, jobDescription, targetRole string) (*models.AnalysisResult, map[string]interface{}, error) {
	apiKey := os.Getenv("GROQ_API_KEY")
	if apiKey == "" {
		return nil, nil, fmt.Errorf("GROQ_API_KEY is not configured on the server")
	}

	systemPrompt := `You are an expert technical recruiter and career coach. You compare a candidate's resume against a target job description and respond with STRICT JSON ONLY, no markdown fences, no commentary, matching exactly this schema:
{
  "match_score": <integer 0-100>,
  "matched_skills": [<string>, ...],
  "partial_skills": [<string>, ...],
  "missing_skills": [<string>, ...],
  "summary": "<2-3 sentence honest summary of fit>",
  "roadmap": [
    {"week": 1, "focus": "<short theme>", "skills": [<string>, ...], "resources": [<string, specific course/doc/project idea>, ...]},
    {"week": 2, "focus": "<short theme>", "skills": [<string>, ...], "resources": [<string>, ...]}
  ]
}
"matched_skills" = clearly demonstrated in the resume and required by the JD.
"partial_skills" = adjacent or related experience exists (e.g. used a similar tool, or has foundational knowledge) but not a strong, direct match.
"missing_skills" = required by the JD with no evidence of it in the resume.
Produce exactly 2 roadmap weeks. Be specific and realistic, not generic.`

	userPrompt := fmt.Sprintf("Target role: %s\n\nRESUME:\n%s\n\nJOB DESCRIPTION:\n%s", targetRole, resumeText, jobDescription)

	reqBody := groqChatRequest{
		Model: "llama-3.1-8b-instant",
		Messages: []groqChatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature: 0.3,
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, nil, err
	}

	httpReq, err := http.NewRequest("POST", groqURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, nil, fmt.Errorf("AI provider error (%d): %s", resp.StatusCode, string(respBytes))
	}

	var groqResp groqChatResponse
	if err := json.Unmarshal(respBytes, &groqResp); err != nil {
		return nil, nil, fmt.Errorf("could not parse AI provider response: %w", err)
	}
	if len(groqResp.Choices) == 0 {
		return nil, nil, fmt.Errorf("AI provider returned no choices")
	}

	raw := strings.TrimSpace(groqResp.Choices[0].Message.Content)
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var result models.AnalysisResult
	if err := json.Unmarshal([]byte(raw), &result); err != nil {
		return nil, nil, fmt.Errorf("could not parse AI analysis JSON: %w", err)
	}

	var rawMap map[string]interface{}
	_ = json.Unmarshal([]byte(raw), &rawMap)

	return &result, rawMap, nil
}

func Analyze(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.UserIDFromContext(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req models.AnalyzeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if strings.TrimSpace(req.ResumeText) == "" || strings.TrimSpace(req.JobDescription) == "" {
		writeError(w, http.StatusBadRequest, "resume_text and job_description are required")
		return
	}

	result, rawMap, err := callGroqAI(req.ResumeText, req.JobDescription, req.TargetRole)
	if err != nil {
		writeError(w, http.StatusBadGateway, "AI analysis failed: "+err.Error())
		return
	}

	matchedJSON, _ := json.Marshal(result.MatchedSkills)
	partialJSON, _ := json.Marshal(result.PartialSkills)
	missingJSON, _ := json.Marshal(result.MissingSkills)
	roadmapJSON, _ := json.Marshal(result.Roadmap)
	rawJSON, _ := json.Marshal(rawMap)

	err = db.Pool.QueryRow(context.Background(),
		`INSERT INTO analyses (user_id, target_role, resume_text, job_description, match_score, matched_skills, partial_skills, missing_skills, roadmap, raw_ai_response)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		 RETURNING id, created_at`,
		userID, req.TargetRole, req.ResumeText, req.JobDescription, result.MatchScore, matchedJSON, partialJSON, missingJSON, roadmapJSON, rawJSON,
	).Scan(&result.ID, &result.CreatedAt)

	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to save analysis: "+err.Error())
		return
	}

	result.TargetRole = req.TargetRole
	writeJSON(w, http.StatusOK, result)
}

func History(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.UserIDFromContext(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	rows, err := db.Pool.Query(context.Background(),
		`SELECT id, target_role, match_score, matched_skills, partial_skills, missing_skills, roadmap, created_at
		 FROM analyses WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`,
		userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to fetch history")
		return
	}
	defer rows.Close()

	results := []models.AnalysisResult{}
	for rows.Next() {
		var a models.AnalysisResult
		var matchedJSON, partialJSON, missingJSON, roadmapJSON []byte
		if err := rows.Scan(&a.ID, &a.TargetRole, &a.MatchScore, &matchedJSON, &partialJSON, &missingJSON, &roadmapJSON, &a.CreatedAt); err != nil {
			continue
		}
		_ = json.Unmarshal(matchedJSON, &a.MatchedSkills)
		_ = json.Unmarshal(partialJSON, &a.PartialSkills)
		_ = json.Unmarshal(missingJSON, &a.MissingSkills)
		_ = json.Unmarshal(roadmapJSON, &a.Roadmap)
		results = append(results, a)
	}

	writeJSON(w, http.StatusOK, results)
}
