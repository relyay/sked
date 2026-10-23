// Package api serves the schedule over HTTP as JSON.
package api

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/relya/vksit/server/internal/schedule"
	"github.com/relya/vksit/server/internal/store"
	"github.com/relya/vksit/server/internal/updater"
)

// Server holds the HTTP handlers.
type Server struct {
	Store       *store.Store
	Updater     *updater.Updater
	Version     string
	AdminSecret string
	Log         *slog.Logger
}

// Handler returns the routed handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("GET /buildings", s.buildings)
	mux.HandleFunc("GET /schedule", s.schedule)
	mux.HandleFunc("GET /groups", s.groups)
	mux.HandleFunc("POST /admin/refresh", s.refresh)
	return s.logRequests(mux)
}

type healthResponse struct {
	Status    string           `json:"status"` // "ok" | "degraded"
	Version   string           `json:"version"`
	LastParse time.Time        `json:"lastParse,omitzero"`
	Sources   []updater.Status `json:"sources"`
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	resp := healthResponse{Status: "ok", Version: s.Version, Sources: s.Updater.Statuses()}
	for _, st := range resp.Sources {
		if st.LastSuccess.After(resp.LastParse) {
			resp.LastParse = st.LastSuccess
		}
		if st.LastSuccess.IsZero() || st.LastError != "" {
			resp.Status = "degraded"
		}
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, resp)
}

type buildingInfo struct {
	Building       int       `json:"building"`
	Source         string    `json:"source"`
	ParsedAt       time.Time `json:"parsedAt"`
	SourceModified time.Time `json:"sourceModified,omitzero"`
}

func (s *Server) buildings(w http.ResponseWriter, r *http.Request) {
	var out []buildingInfo
	var newest time.Time
	for _, snap := range s.Store.Buildings() {
		out = append(out, buildingInfo{snap.Building, snap.Source, snap.ParsedAt, snap.SourceModified})
		if snap.ParsedAt.After(newest) {
			newest = snap.ParsedAt
		}
	}
	if out == nil {
		out = []buildingInfo{}
	}
	s.writeCached(w, r, newest, map[string]any{"buildings": out})
}

type scheduleResponse struct {
	Building       int            `json:"building"`
	Source         string         `json:"source"`
	ParsedAt       time.Time      `json:"parsedAt"`
	SourceModified time.Time      `json:"sourceModified,omitzero"`
	Days           []schedule.Day `json:"days"`
}

func (s *Server) schedule(w http.ResponseWriter, r *http.Request) {
	snap, ok := s.view(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	date := q.Get("date")
	if date != "" {
		if _, err := time.Parse(time.DateOnly, date); err != nil {
			writeError(w, http.StatusBadRequest, "date must be YYYY-MM-DD")
			return
		}
	}
	group := strings.TrimSpace(q.Get("group"))

	days := []schedule.Day{}
	for _, d := range snap.Days {
		if date != "" && d.Date != date {
			continue
		}
		if group != "" {
			// Keep the day even without the group: an empty day is meaningful.
			var groups []schedule.GroupDay
			for _, g := range d.Groups {
				if g.Group == group {
					groups = append(groups, g)
				}
			}
			if groups == nil {
				groups = []schedule.GroupDay{}
			}
			d.Groups = groups
		}
		days = append(days, d)
	}
	s.writeCached(w, r, snap.ParsedAt, scheduleResponse{snap.Building, snap.Source, snap.ParsedAt, snap.SourceModified, days})
}

func (s *Server) groups(w http.ResponseWriter, r *http.Request) {
	snap, ok := s.view(w, r)
	if !ok {
		return
	}
	groups := snap.Groups()
	if groups == nil {
		groups = []schedule.Group{}
	}
	s.writeCached(w, r, snap.ParsedAt, map[string]any{"building": snap.Building, "groups": groups})
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	got := r.Header.Get("X-Admin-Secret")
	if s.AdminSecret == "" || subtle.ConstantTimeCompare([]byte(got), []byte(s.AdminSecret)) != 1 {
		writeError(w, http.StatusForbidden, "invalid admin secret")
		return
	}
	err := s.Updater.Refresh(r.Context(), true)
	status := http.StatusOK
	resp := map[string]any{"sources": s.Updater.Statuses()}
	if err != nil {
		status = http.StatusBadGateway
		resp["error"] = err.Error()
	}
	writeJSON(w, status, resp)
}

// view resolves ?building= to a snapshot, writing the error response itself.
func (s *Server) view(w http.ResponseWriter, r *http.Request) (schedule.Snapshot, bool) {
	b, err := strconv.Atoi(r.URL.Query().Get("building"))
	if err != nil || b < 1 {
		writeError(w, http.StatusBadRequest, "building must be a positive number, e.g. building=1")
		return schedule.Snapshot{}, false
	}
	snap, ok := s.Store.View(b)
	if !ok {
		if len(s.Store.Buildings()) == 0 {
			w.Header().Set("Retry-After", "30")
			writeError(w, http.StatusServiceUnavailable, "schedule has not been loaded yet")
		} else {
			writeError(w, http.StatusNotFound, "unknown building")
		}
		return schedule.Snapshot{}, false
	}
	return snap, true
}

// writeCached writes v with a content-hash ETag and answers conditional
// requests with 304.
func (s *Server) writeCached(w http.ResponseWriter, r *http.Request, modified time.Time, v any) {
	body, err := json.Marshal(v)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "encode response")
		return
	}
	sum := sha256.Sum256(body)
	etag := `"` + hex.EncodeToString(sum[:16]) + `"`
	h := w.Header()
	h.Set("ETag", etag)
	h.Set("Cache-Control", "no-cache")
	if !modified.IsZero() {
		h.Set("Last-Modified", modified.UTC().Format(http.TimeFormat))
	}
	if etagMatches(r.Header.Get("If-None-Match"), etag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	h.Set("Content-Type", "application/json; charset=utf-8")
	h.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(http.StatusOK)
	w.Write(body)
}

func etagMatches(header, etag string) bool {
	for candidate := range strings.SplitSeq(header, ",") {
		candidate = strings.TrimPrefix(strings.TrimSpace(candidate), "W/")
		if candidate == etag || candidate == "*" {
			return true
		}
	}
	return false
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		s.Log.Debug("http", "method", r.Method, "path", r.URL.Path, "query", r.URL.RawQuery,
			"status", rec.status, "duration", time.Since(start))
	})
}
