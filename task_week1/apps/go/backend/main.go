// Notes API with Go + Gin + Redis. Same contract as every other backend: ../../../API.md
//
// Redis is a key-value store (no tables, no SQL). The notes are stored like this:
//
//	notes:next_id     STRING  counter; INCR gives the next id (1, 2, 3...)
//	note:<id>         HASH    one note: text, done ("1"/"0"), dueDate ("" = null), createdAt
//	notes:by_id       ZSET    sorted set of all ids (score = id), to list them newest first
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
	"github.com/redis/go-redis/v9"
)

const (
	keyNextID = "notes:next_id"
	keyIndex  = "notes:by_id"
)

func noteKey(id int64) string { return "note:" + strconv.FormatInt(id, 10) }

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

// ---- Redis <-> Note ----

type store struct{ rdb *redis.Client }

func toNote(id int64, h map[string]string) Note {
	n := Note{ID: id, Text: h["text"], Done: h["done"] == "1", CreatedAt: h["createdAt"]}
	if d := h["dueDate"]; d != "" {
		n.DueDate = &d
	}
	return n
}

func boolFlag(b bool) string {
	if b {
		return "1"
	}
	return "0"
}

func (s *store) get(ctx context.Context, id int64) (Note, bool, error) {
	h, err := s.rdb.HGetAll(ctx, noteKey(id)).Result() // missing key -> empty map, not an error
	if err != nil || len(h) == 0 {
		return Note{}, false, err
	}
	return toNote(id, h), true, nil
}

func (s *store) list(ctx context.Context) ([]Note, error) {
	ids, err := s.rdb.ZRevRange(ctx, keyIndex, 0, -1).Result() // highest id first = newest first
	if err != nil {
		return nil, err
	}
	// Pipeline: send all HGETALL commands in ONE round trip instead of one per note.
	pipe := s.rdb.Pipeline()
	cmds := make([]*redis.MapStringStringCmd, len(ids))
	for i, raw := range ids {
		id, _ := strconv.ParseInt(raw, 10, 64)
		cmds[i] = pipe.HGetAll(ctx, noteKey(id))
	}
	if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, redis.Nil) {
		return nil, err
	}
	notes := make([]Note, 0, len(ids)) // never nil: an empty list must be JSON [] not null
	for i, raw := range ids {
		if h := cmds[i].Val(); len(h) > 0 {
			id, _ := strconv.ParseInt(raw, 10, 64)
			notes = append(notes, toNote(id, h))
		}
	}
	return notes, nil
}

func (s *store) create(ctx context.Context, in noteInput) (Note, error) {
	id, err := s.rdb.Incr(ctx, keyNextID).Result()
	if err != nil {
		return Note{}, err
	}
	fields := map[string]any{
		"text":      in.text,
		"done":      boolFlag(in.done),
		"dueDate":   in.dueDate,
		"createdAt": time.Now().UTC().Format("2006-01-02T15:04:05.000Z"),
	}
	// TxPipelined = MULTI ... EXEC: both commands are applied together or not at all.
	_, err = s.rdb.TxPipelined(ctx, func(p redis.Pipeliner) error {
		p.HSet(ctx, noteKey(id), fields)
		p.ZAdd(ctx, keyIndex, redis.Z{Score: float64(id), Member: id})
		return nil
	})
	if err != nil {
		return Note{}, err
	}
	n, _, err := s.get(ctx, id)
	return n, err
}

func (s *store) update(ctx context.Context, id int64, in noteInput) (Note, bool, error) {
	exists, err := s.rdb.Exists(ctx, noteKey(id)).Result()
	if err != nil || exists == 0 {
		return Note{}, false, err
	}
	// Full replace (PUT): dueDate left out -> "" -> null. createdAt is kept.
	err = s.rdb.HSet(ctx, noteKey(id), "text", in.text, "done", boolFlag(in.done), "dueDate", in.dueDate).Err()
	if err != nil {
		return Note{}, false, err
	}
	return s.get(ctx, id)
}

func (s *store) delete(ctx context.Context, id int64) (bool, error) {
	var del *redis.IntCmd
	_, err := s.rdb.TxPipelined(ctx, func(p redis.Pipeliner) error {
		del = p.Del(ctx, noteKey(id))
		p.ZRem(ctx, keyIndex, id)
		return nil
	})
	return err == nil && del.Val() == 1, err
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
		c.JSON(http.StatusOK, gin.H{"status": "ok", "backend": "Go + Gin + Redis"})
	})

	api.GET("/notes", func(c *gin.Context) {
		notes, err := s.list(c)
		if err != nil {
			fail(c, err)
			return
		}
		c.JSON(http.StatusOK, notes)
	})

	api.GET("/notes/:id", func(c *gin.Context) {
		id, ok := parseID(c.Param("id"))
		if !ok {
			fail(c, notFound(c.Param("id")))
			return
		}
		n, found, err := s.get(c, id)
		if err == nil && !found {
			err = notFound(c.Param("id"))
		}
		if err != nil {
			fail(c, err)
			return
		}
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
	rdb := redis.NewClient(&redis.Options{Addr: getenv("REDIS_ADDR", "localhost:6379")})

	// Fail fast: if Redis is unreachable at startup, exit (compose/Docker restarts us) instead of
	// starting a server that answers 500 to everything.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Fatalf("cannot reach Redis: %v", err)
	}

	srv := &http.Server{
		Addr:              ":" + getenv("PORT", "8080"),
		Handler:           routes(&store{rdb: rdb}),
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
	_ = rdb.Close()
}
