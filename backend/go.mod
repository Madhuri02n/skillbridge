module skillbridge

go 1.21

require (
	github.com/go-chi/chi/v5 v5.0.12
	github.com/go-chi/cors v1.2.1
	github.com/golang-jwt/jwt/v5 v5.2.1
	github.com/jackc/pgx/v5 v5.5.5
	golang.org/x/crypto v0.21.0
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20221227161230-091c0ba34f0a // indirect
	github.com/jackc/puddle/v2 v2.2.1 // indirect
	golang.org/x/sync v0.1.0 // indirect
	golang.org/x/text v0.14.0 // indirect
)

replace golang.org/x/crypto => github.com/golang/crypto v0.21.0

replace golang.org/x/text => github.com/golang/text v0.14.0

replace golang.org/x/sync => github.com/golang/sync v0.6.0

replace gopkg.in/yaml.v3 => github.com/go-yaml/yaml v3.0.1+incompatible

replace gopkg.in/check.v1 => github.com/go-check/check v0.0.0-20180628173108-788fd7840127
