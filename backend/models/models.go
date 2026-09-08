package models

import "time"

type User struct {
	ID           int       `json:"id"`
	Name         string    `json:"name"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"created_at"`
}

type RegisterRequest struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type AuthResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

type AnalyzeRequest struct {
	TargetRole      string `json:"target_role"`
	ResumeText      string `json:"resume_text"`
	JobDescription  string `json:"job_description"`
}

type InterviewPrepRequest struct {
	TargetRole     string   `json:"target_role"`
	ResumeText     string   `json:"resume_text"`
	JobDescription string   `json:"job_description"`
	MissingSkills  []string `json:"missing_skills"`
}

type InterviewPrepResult struct {
	TechnicalQuestions   []string `json:"technical_questions"`
	GapQuestions         []GapQuestion `json:"gap_questions"`
	BehavioralQuestions  []string `json:"behavioral_questions"`
}

type GapQuestion struct {
	Question    string `json:"question"`
	WhyAsked    string `json:"why_asked"`
}

type RoadmapItem struct {
	Week      int      `json:"week"`
	Focus     string   `json:"focus"`
	Skills    []string `json:"skills"`
	Resources []string `json:"resources"`
}

type AnalysisResult struct {
	ID             int           `json:"id"`
	TargetRole     string        `json:"target_role"`
	MatchScore     int           `json:"match_score"`
	MatchedSkills  []string      `json:"matched_skills"`
	PartialSkills  []string      `json:"partial_skills"`
	MissingSkills  []string      `json:"missing_skills"`
	Summary        string        `json:"summary"`
	Roadmap        []RoadmapItem `json:"roadmap"`
	CreatedAt      time.Time     `json:"created_at,omitempty"`
}
