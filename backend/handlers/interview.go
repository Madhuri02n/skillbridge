package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"skillbridge/middleware"
	"skillbridge/models"
)

func callGroqInterviewPrep(req models.InterviewPrepRequest) (*models.InterviewPrepResult, error) {
	apiKey := os.Getenv("GROQ_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GROQ_API_KEY is not configured on the server")
	}

	systemPrompt := `You are an expert technical interviewer preparing a candidate for a real interview. Respond with STRICT JSON ONLY, no markdown fences, no commentary, matching exactly this schema:
{
  "technical_questions": [<string>, ...],
  "gap_questions": [
    {"question": "<string>", "why_asked": "<one sentence explaining why this question relates to a specific skill gap>"}
  ],
  "behavioral_questions": [<string>, ...]
}
Generate 4-5 technical_questions based on the skills actually required by the job description.
Generate 2-3 gap_questions specifically probing the candidate's weakest/missing areas, each with a short "why_asked" explanation.
Generate 3 standard behavioral_questions relevant to the role level.
Be specific to this resume and job, not generic filler questions.`

	userPrompt := fmt.Sprintf(
		"Target role: %s\n\nRESUME:\n%s\n\nJOB DESCRIPTION:\n%s\n\nKNOWN MISSING SKILLS:\n%s",
		req.TargetRole, req.ResumeText, req.JobDescription, strings.Join(req.MissingSkills, ", "),
	)

	reqBody := groqChatRequest{
		Model: "openai/gpt-oss-120b",
		Messages: []groqChatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature: 0.4,
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	httpReq, err := http.NewRequest("POST", groqURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json; charset=utf-8")
	httpReq.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("AI provider error (%d): %s", resp.StatusCode, string(respBytes))
	}

	var groqResp groqChatResponse
	if err := json.Unmarshal(respBytes, &groqResp); err != nil {
		return nil, fmt.Errorf("could not parse AI provider response: %w", err)
	}
	if len(groqResp.Choices) == 0 {
		return nil, fmt.Errorf("AI provider returned no choices")
	}

	raw := strings.TrimSpace(groqResp.Choices[0].Message.Content)
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var result models.InterviewPrepResult
	if err := json.Unmarshal([]byte(raw), &result); err != nil {
		return nil, fmt.Errorf("could not parse interview prep JSON: %w", err)
	}

	return &result, nil
}

func InterviewPrep(w http.ResponseWriter, r *http.Request) {
	_, ok := middleware.UserIDFromContext(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req models.InterviewPrepRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if strings.TrimSpace(req.ResumeText) == "" || strings.TrimSpace(req.JobDescription) == "" {
		writeError(w, http.StatusBadRequest, "resume_text and job_description are required")
		return
	}

	result, err := callGroqInterviewPrep(req)
	if err != nil {
		writeError(w, http.StatusBadGateway, "Interview prep generation failed: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, result)
}
