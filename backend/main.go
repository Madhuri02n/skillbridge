package main

import (
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"

	"skillbridge/db"
	"skillbridge/handlers"
	"skillbridge/middleware"
)

func main() {
	if err := db.Connect(); err != nil {
		log.Fatalf("database connection failed: %v", err)
	}
	log.Println("connected to database")

	r := chi.NewRouter()
	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		AllowCredentials: false,
		MaxAge:           300,
	}))

	r.Get("/api/health", handlers.Health)
	r.Post("/api/auth/register", handlers.Register)
	r.Post("/api/auth/login", handlers.Login)

	r.Group(func(protected chi.Router) {
		protected.Use(middleware.RequireAuth)
		protected.Post("/api/analyze", handlers.Analyze)
		protected.Get("/api/history", handlers.History)
		protected.Post("/api/interview-prep", handlers.InterviewPrep)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("SkillBridge API listening on :%s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatal(err)
	}
}
