// Package api serves the schedule over HTTP as JSON.
package api

import (
	"cmp"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net/http"
	"slices"
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
	Building       int            `json:"building,omitempty"` // set when filtered by building
	Group          string         `json:"group,omitempty"`
	ParsedAt       time.Time      `json:"parsedAt"`
	SourceModified time.Time      `json:"sourceModified,omitzero"`
	Days           []schedule.Day `json:"days"`
}

// schedule serves one building, one group across all buildings, or both
// filters combined. Groups move between buildings from day to day, so the
// client asks by group and reads the building from each lesson.
func (s *Server) schedule(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	group := strings.TrimSpace(q.Get("group"))
	if q.Get("building") == "" && group == "" {
		writeError(w, http.StatusBadRequest, "pass group=… and/or building=…")
		return
	}
	snaps, building, ok := s.snapshots(w, r)
	if !ok {
		return
	}
	date := q.Get("date")
	if date != "" {
		if _, err := time.Parse(time.DateOnly, date); err != nil {
			writeError(w, http.StatusBadRequest, "date must be YYYY-MM-DD")
			return
		}
	}

	resp := scheduleResponse{Building: building, Group: group, Days: []schedule.Day{}}
	byDate := map[string]int{}
	for _, snap := range snaps {
		if snap.ParsedAt.After(resp.ParsedAt) {
			resp.ParsedAt = snap.ParsedAt
		}
		if snap.SourceModified.After(resp.SourceModified) {
			resp.SourceModified = snap.SourceModified
		}
		for _, d := range snap.Days {
			if date != "" && d.Date != date {
				continue
			}
			if group != "" {
				// Keep the day even without the group: an empty day is meaningful.
				d.Groups = filterGroup(d.Groups, group)
			}
			i, seen := byDate[d.Date]
			if !seen {
				byDate[d.Date] = len(resp.Days)
				resp.Days = append(resp.Days, d)
				continue
			}
			resp.Days[i].Groups = mergeGroups(resp.Days[i].Groups, d.Groups)
		}
	}
	slices.SortFunc(resp.Days, func(a, b schedule.Day) int { return cmp.Compare(a.Date, b.Date) })
	s.writeCached(w, r, resp.ParsedAt, resp)
}

func filterGroup(groups []schedule.GroupDay, name string) []schedule.GroupDay {
	out := []schedule.GroupDay{}
	for _, g := range groups {
		if g.Group == name {
			out = append(out, g)
		}
	}
	return out
}

// mergeGroups joins the same date from two buildings; lessons keep their
// own building.
func mergeGroups(into, from []schedule.GroupDay) []schedule.GroupDay {
	into = slices.Clone(into)
	for _, g := range from {
		i := slices.IndexFunc(into, func(x schedule.GroupDay) bool { return x.Group == g.Group })
		if i < 0 {
			into = append(into, g)
			continue
		}
		into[i].Lessons = append(slices.Clone(into[i].Lessons), g.Lessons...)
		slices.SortStableFunc(into[i].Lessons, func(a, b schedule.Lesson) int {
			return cmp.Or(cmp.Compare(a.Pair, b.Pair), cmp.Compare(a.Subgroup, b.Subgroup))
		})
		into[i].Notes = append(slices.Clone(into[i].Notes), g.Notes...)
	}
	return into
}

func (s *Server) groups(w http.ResponseWriter, r *http.Request) {
	snaps, building, ok := s.snapshots(w, r)
	if !ok {
		return
	}
	var newest time.Time
	for _, snap := range snaps {
		if snap.ParsedAt.After(newest) {
			newest = snap.ParsedAt
		}
	}
	groups := schedule.Groups(snaps...)
	if groups == nil {
		groups = []schedule.Group{}
	}
	resp := map[string]any{"groups": groups}
	if building != 0 {
		resp["building"] = building
	}
	s.writeCached(w, r, newest, resp)
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

// snapshots resolves the optional ?building= filter, writing the error
// response itself. Without the filter all buildings are returned.
func (s *Server) snapshots(w http.ResponseWriter, r *http.Request) ([]schedule.Snapshot, int, bool) {
	all := s.Store.Views()
	if len(all) == 0 {
		w.Header().Set("Retry-After", "30")
		writeError(w, http.StatusServiceUnavailable, "schedule has not been loaded yet")
		return nil, 0, false
	}
	raw := r.URL.Query().Get("building")
	if raw == "" {
		return all, 0, true
	}
	b, err := strconv.Atoi(raw)
	if err != nil || b < 1 {
		writeError(w, http.StatusBadRequest, "building must be a positive number, e.g. building=1")
		return nil, 0, false
	}
	for _, snap := range all {
		if snap.Building == b {
			return []schedule.Snapshot{snap}, b, true
		}
	}
	writeError(w, http.StatusNotFound, "unknown building")
	return nil, 0, false
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
