// Notes API with Go + Gin + PostgreSQL (main database) + Redis (cache).
// Same contract as every other backend: ../../../API.md
//
// "Cache-aside" pattern:
//
//	READ : ask Redis first -> HIT: answer from RAM (fast)
//	                       -> MISS: read PostgreSQL, keep a copy in Redis for 60 s, answer
//	WRITE: write PostgreSQL (the truth) -> DELETE the cached copies that are now stale
//
// Redis keys: "cache:notes" (the whole list as JSON), "cache:note:<id>" (one note as JSON).
// Redis is only a speed-up: if it is down, every request simply goes to PostgreSQL.
// Responses carry a header "X-Cache: HIT|MISS" so you can watch the cache work (curl -i).
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

const (
	cacheTTL     = 60 * time.Second // a cached copy lives at most 60 s, even if we forget to delete it
	cacheListKey = "cache:notes"
)

func cacheNoteKey(id int64) string { return "cache:note:" + strconv.FormatInt(id, 10) }

// Note is the JSON shape of API.md. The `json:"..."` tags give the field names in JSON.
type Note struct {
	ID        int64   `json:"id"`
	Text      string  `json:"text"`
	Done      bool    `json:"done"`
	DueDate   *string `json:"dueDate"` // pointer: nil becomes JSON null
	CreatedAt string  `json:"createdAt"`
}

// ---- Errors: every failure becomes {"error": {"code", "message"}} ----

type apiError struct {
	status  int
	code    string
	message string
}

func (e *apiError) Error() string { return e.message }

func notFound(id string) *apiError {
	return &apiError{http.StatusNotFound, "NOT_FOUND", fmt.Sprintf("Note %s not found", id)}
}

func invalid(msg string) *apiError {
	return &apiError{http.StatusBadRequest, "VALIDATION_ERROR", msg}
}

// fail answers with the API error format. Any other error is a bug or a Redis problem:
// log it and answer 500 without details (never leak internals to the client).
func fail(c *gin.Context, err error) {
	var ae *apiError
	if !errors.As(err, &ae) {
		log.Printf("unexpected error on %s %s: %v", c.Request.Method, c.Request.URL.Path, err)
		ae = &apiError{http.StatusInternalServerError, "INTERNAL_ERROR", "Unexpected server error"}
	}
	c.AbortWithStatusJSON(ae.status, gin.H{"error": gin.H{"code": ae.code, "message": ae.message}})
}

// ---- Validation ----

var (
	idPattern   = regexp.MustCompile(`^[0-9]{1,18}$`) // fits in int64
	datePattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}$`)
)

// parseID: a malformed id ("does-not-exist") is treated as "not found", like every backend.
func parseID(raw string) (int64, bool) {
	if !idPattern.MatchString(raw) {
		return 0, false
	}
	id, err := strconv.ParseInt(raw, 10, 64)
	return id, err == nil
}

type noteInput struct {
	text    string
	done    bool
	dueDate string // "" = no deadline (null)
}

// readInput reads the body ourselves (instead of c.ShouldBindJSON into a struct) so we can return
// exactly the codes of API.md: INVALID_JSON vs VALIDATION_ERROR, and "done must be a boolean".
func readInput(c *gin.Context) (noteInput, error) {
	raw, err := io.ReadAll(c.Request.Body)
	if err != nil {
		return noteInput{}, err
	}
	var parsed any // any JSON value: object, array, string...
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return noteInput{}, &apiError{http.StatusBadRequest, "INVALID_JSON", "Request body is not valid JSON"}
	}
	body, _ := parsed.(map[string]any) // not an object -> empty map -> "text is required"

	text, _ := body["text"].(string)
	text = strings.TrimSpace(text)
	if text == "" {
		return noteInput{}, invalid("text is required")
	}
	if utf8.RuneCountInString(text) > 200 { // characters, not bytes ("ế" is 3 bytes)
		return noteInput{}, invalid("text must be at most 200 characters")
	}

	done := false
	if v, ok := body["done"]; ok {
		if done, ok = v.(bool); !ok {
			return noteInput{}, invalid("done must be a boolean")
		}
	}

	due := ""
	if v, ok := body["dueDate"]; ok && v != nil {
		s, isString := v.(string)
		// time.Parse checks the calendar too: "2026-02-30" -> error "day out of range"
		if _, err := time.Parse(time.DateOnly, s); !isString || !datePattern.MatchString(s) || err != nil {
			return noteInput{}, invalid("dueDate must be a date in YYYY-MM-DD format or null")
		}
		due = s
	}
	return noteInput{text: text, done: done, dueDate: due}, nil
}

// ---- PostgreSQL (the truth) + Redis (cache) ----

type store struct {
	db    *pgxpool.Pool // a POOL keeps a few connections open and lends them to requests
	cache *redis.Client
}

const noteColumns = "id, text, done, to_char(due_date, 'YYYY-MM-DD'), " +
	`to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`

// scanNote reads one row in the order of noteColumns. due_date can be NULL -> *string nil -> JSON null.
func scanNote(row pgx.Row) (Note, error) {
	var n Note
	err := row.Scan(&n.ID, &n.Text, &n.Done, &n.DueDate, &n.CreatedAt)
	return n, err
}

func nullable(s string) *string { // "" (no deadline) -> SQL NULL
	if s == "" {
		return nil
	}
	return &s
}

// cacheGet: true only on a real hit. A Redis error is logged and treated as a miss.
func (s *store) cacheGet(ctx context.Context, key string, dst any) bool {
	raw, err := s.cache.Get(ctx, key).Bytes()
	if err != nil {
		if !errors.Is(err, redis.Nil) { // redis.Nil = key does not exist (a normal miss)
			log.Printf("cache get %s: %v", key, err)
		}
		return false
	}
	return json.Unmarshal(raw, dst) == nil
}

func (s *store) cacheSet(ctx context.Context, key string, v any) {
	raw, _ := json.Marshal(v)
	if err := s.cache.Set(ctx, key, raw, cacheTTL).Err(); err != nil {
		log.Printf("cache set %s: %v", key, err)
	}
}

// invalidate deletes the copies a write made stale: the list, and the note itself.
func (s *store) invalidate(ctx context.Context, id int64) {
	if err := s.cache.Del(ctx, cacheListKey, cacheNoteKey(id)).Err(); err != nil {
		log.Printf("cache invalidate: %v", err)
	}
}

func (s *store) list(ctx context.Context) ([]Note, bool, error) {
	var notes []Note
	if s.cacheGet(ctx, cacheListKey, &notes) {
		return notes, true, nil
	}
	rows, err := s.db.Query(ctx, "SELECT "+noteColumns+" FROM notes ORDER BY id DESC")
	if err != nil {
		return nil, false, err
	}
	// CollectRows calls scanNote for every row and closes the result set.
	notes, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Note, error) { return scanNote(r) })
	if err != nil {
		return nil, false, err
	}
	if notes == nil {
		notes = []Note{} // an empty list must be JSON [] not null
	}
	s.cacheSet(ctx, cacheListKey, notes)
	return notes, false, nil
}

func (s *store) get(ctx context.Context, id int64) (Note, bool, bool, error) {
	var n Note
	if s.cacheGet(ctx, cacheNoteKey(id), &n) {
		return n, true, true, nil
	}
	// $1 = placeholder: the value is sent separately -> no SQL injection
	n, err := scanNote(s.db.QueryRow(ctx, "SELECT "+noteColumns+" FROM notes WHERE id = $1", id))
	if errors.Is(err, pgx.ErrNoRows) {
		return Note{}, false, false, nil
	}
	if err != nil {
		return Note{}, false, false, err
	}
	s.cacheSet(ctx, cacheNoteKey(id), n)
	return n, true, false, nil
}

func (s *store) create(ctx context.Context, in noteInput) (Note, error) {
	n, err := scanNote(s.db.QueryRow(ctx,
		"INSERT INTO notes (text, done, due_date) VALUES ($1, $2, $3) RETURNING "+noteColumns,
		in.text, in.done, nullable(in.dueDate)))
	if err == nil {
		s.invalidate(ctx, n.ID)
	}
	return n, err
}

func (s *store) update(ctx context.Context, id int64, in noteInput) (Note, bool, error) {
	// Full replace (PUT): dueDate left out -> NULL. created_at is kept.
	n, err := scanNote(s.db.QueryRow(ctx,
		"UPDATE notes SET text = $1, done = $2, due_date = $3 WHERE id = $4 RETURNING "+noteColumns,
		in.text, in.done, nullable(in.dueDate), id))
	if errors.Is(err, pgx.ErrNoRows) {
		return Note{}, false, nil
	}
	if err != nil {
		return Note{}, false, err
	}
	s.invalidate(ctx, id)
	return n, true, nil
}

func (s *store) delete(ctx context.Context, id int64) (bool, error) {
	tag, err := s.db.Exec(ctx, "DELETE FROM notes WHERE id = $1", id)
	if err != nil {
		return false, err
	}
	s.invalidate(ctx, id)
	return tag.RowsAffected() == 1, nil
}

func cacheHeader(c *gin.Context, hit bool) {
	if hit {
		c.Header("X-Cache", "HIT")
	} else {
		c.Header("X-Cache", "MISS")
	}
}

// ---- HTTP ----

func routes(s *store) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger()) // one log line per request
	// A panic in a handler becomes a 500 JSON instead of crashing the server.
	r.Use(gin.CustomRecovery(func(c *gin.Context, rec any) {
		fail(c, fmt.Errorf("panic: %v", rec))
	}))
	// Unknown route -> 404 JSON (Gin also answers wrong methods with 404 by default).
	r.NoRoute(func(c *gin.Context) {
		fail(c, &apiError{http.StatusNotFound, "NOT_FOUND", "Route " + c.Request.URL.Path + " not found"})
	})

	api := r.Group("/api")

	api.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "backend": "Go + Gin + PostgreSQL + Redis cache"})
	})

	api.GET("/notes", func(c *gin.Context) {
		notes, hit, err := s.list(c)
		if err != nil {
			fail(c, err)
			return
		}
		cacheHeader(c, hit)
		c.JSON(http.StatusOK, notes)
	})

	api.GET("/notes/:id", func(c *gin.Context) {
		id, ok := parseID(c.Param("id"))
		if !ok {
			fail(c, notFound(c.Param("id")))
			return
		}
		n, found, hit, err := s.get(c, id)
		if err == nil && !found {
			err = notFound(c.Param("id"))
		}
		if err != nil {
			fail(c, err)
			return
		}
		cacheHeader(c, hit)
		c.JSON(http.StatusOK, n)
	})

	api.POST("/notes", func(c *gin.Context) {
		in, err := readInput(c)
		if err != nil {
			fail(c, err)
			return
		}
		n, err := s.create(c, in)
		if err != nil {
			fail(c, err)
			return
		}
		c.JSON(http.StatusCreated, n)
	})

	api.PUT("/notes/:id", func(c *gin.Context) {
		id, ok := parseID(c.Param("id"))
		if !ok {
			fail(c, notFound(c.Param("id")))
			return
		}
		in, err := readInput(c)
		if err != nil {
			fail(c, err)
			return
		}
		n, found, err := s.update(c, id, in)
		if err == nil && !found {
			err = notFound(c.Param("id"))
		}
		if err != nil {
			fail(c, err)
			return
		}
		c.JSON(http.StatusOK, n)
	})

	api.DELETE("/notes/:id", func(c *gin.Context) {
		id, ok := parseID(c.Param("id"))
		if !ok {
			fail(c, notFound(c.Param("id")))
			return
		}
		deleted, err := s.delete(c, id)
		if err == nil && !deleted {
			err = notFound(c.Param("id"))
		}
		if err != nil {
			fail(c, err)
			return
		}
		c.Status(http.StatusNoContent)
	})

	return r
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	db, err := pgxpool.New(ctx, getenv("DATABASE_URL", "postgres://notes:notes@localhost:5432/notesdb"))
	if err != nil {
		log.Fatalf("bad DATABASE_URL: %v", err)
	}
	// Fail fast: PostgreSQL holds the data, so without it there is no point in starting.
	if err := db.Ping(ctx); err != nil {
		log.Fatalf("cannot reach PostgreSQL: %v", err)
	}

	cache := redis.NewClient(&redis.Options{Addr: getenv("REDIS_ADDR", "localhost:6379")})
	// Redis is only a cache: if it is down we still start (every request just goes to PostgreSQL).
	if err := cache.Ping(ctx).Err(); err != nil {
		log.Printf("WARNING: Redis unreachable, running without cache: %v", err)
	}

	srv := &http.Server{
		Addr:              ":" + getenv("PORT", "8080"),
		Handler:           routes(&store{db: db, cache: cache}),
		ReadHeaderTimeout: 5 * time.Second, // protects against clients that never finish sending headers
	}

	// Graceful shutdown: on "docker stop" (SIGTERM), stop accepting new requests and let the
	// running ones finish (max 10 s) before exiting.
	go func() {
		log.Printf("listening on %s", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Print("shutting down")
	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancelShutdown()
	_ = srv.Shutdown(shutdownCtx)
	db.Close()
	_ = cache.Close()
}
