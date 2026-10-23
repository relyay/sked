package api

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/relya/vksit/server/internal/schedule"
	"github.com/relya/vksit/server/internal/source"
	"github.com/relya/vksit/server/internal/store"
	"github.com/relya/vksit/server/internal/updater"
)

// fakeOrigin serves the real test PDFs like rasp.vksit.ru (nginx ETags) and
// can be switched to failing.
type fakeOrigin struct {
	failing atomic.Bool
	gets    atomic.Int32
}

func (o *fakeOrigin) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if o.failing.Load() {
		http.Error(w, "down", http.StatusBadGateway)
		return
	}
	o.gets.Add(1)
	f, err := os.Open(filepath.Join("../../testdata", filepath.Base(r.URL.Path)))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer f.Close()
	w.Header().Set("ETag", `"`+filepath.Base(r.URL.Path)+`-v1"`)
	http.ServeContent(w, r, r.URL.Path, time.Date(2026, 10, 23, 8, 52, 0, 0, time.UTC), f)
}

type env struct {
	t       *testing.T
	origin  *fakeOrigin
	server  *httptest.Server
	updater *updater.Updater
	dir     string
}

func newEnv(t *testing.T, dir string) *env {
	t.Helper()
	origin := &fakeOrigin{}
	originSrv := httptest.NewServer(origin)
	t.Cleanup(originSrv.Close)

	st, err := store.Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	up := updater.New([]updater.Source{
		{Name: "npo", Fetcher: &source.Fetcher{URL: originSrv.URL + "/npo.pdf"}},
		{Name: "spo", Fetcher: &source.Fetcher{URL: originSrv.URL + "/spo.pdf"}},
	}, st, log)
	up.Now = func() time.Time { return time.Date(2026, 10, 23, 9, 0, 0, 0, time.UTC) }

	srv := httptest.NewServer((&Server{Store: st, Updater: up, Version: "test", AdminSecret: "s3cret", Log: log}).Handler())
	t.Cleanup(srv.Close)
	return &env{t: t, origin: origin, server: srv, updater: up, dir: dir}
}

func (e *env) get(path string, header http.Header, v any) *http.Response {
	e.t.Helper()
	req, _ := http.NewRequest(http.MethodGet, e.server.URL+path, nil)
	for k, vs := range header {
		req.Header[k] = vs
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer resp.Body.Close()
	if v != nil && resp.StatusCode == http.StatusOK {
		if err := json.NewDecoder(resp.Body).Decode(v); err != nil {
			e.t.Fatal(err)
		}
	}
	return resp
}

func TestNotLoadedYet(t *testing.T) {
	e := newEnv(t, t.TempDir())
	if resp := e.get("/schedule?building=1", nil, nil); resp.StatusCode != http.StatusServiceUnavailable {
		t.Errorf("status = %d, want 503", resp.StatusCode)
	}
	var h healthResponse
	if resp := e.get("/health", nil, &h); resp.StatusCode != http.StatusOK || h.Status != "degraded" || h.Version != "test" {
		t.Errorf("health = %d %+v", resp.StatusCode, h)
	}
}

func TestScheduleEndpoints(t *testing.T) {
	e := newEnv(t, t.TempDir())
	if err := e.updater.Refresh(context.Background(), false); err != nil {
		t.Fatal(err)
	}

	var h healthResponse
	e.get("/health", nil, &h)
	if h.Status != "ok" || h.LastParse.IsZero() || len(h.Sources) != 2 {
		t.Errorf("health = %+v", h)
	}

	var all scheduleResponse
	resp := e.get("/schedule?building=1", nil, &all)
	if resp.StatusCode != http.StatusOK || all.Building != 1 || len(all.Days) != 3 {
		t.Fatalf("schedule = %d building=%d days=%d", resp.StatusCode, all.Building, len(all.Days))
	}
	etag := resp.Header.Get("ETag")
	if etag == "" || resp.Header.Get("Last-Modified") == "" {
		t.Errorf("missing validators: %v", resp.Header)
	}
	if resp := e.get("/schedule?building=1", http.Header{"If-None-Match": {etag}}, nil); resp.StatusCode != http.StatusNotModified {
		t.Errorf("conditional GET = %d, want 304", resp.StatusCode)
	}

	var one scheduleResponse
	e.get("/schedule?building=2&date=2026-10-24&group=ИСП-324а", nil, &one)
	if one.Building != 2 || len(one.Days) != 1 || one.Days[0].Date != "2026-10-24" || len(one.Days[0].Groups) > 1 {
		t.Errorf("filtered = %+v", one)
	}

	var missing scheduleResponse
	e.get("/schedule?building=1&date=2026-10-25", nil, &missing)
	if len(missing.Days) != 0 {
		t.Errorf("sunday should be empty, got %+v", missing.Days)
	}

	var groups struct {
		Groups []schedule.Group `json:"groups"`
	}
	e.get("/groups?building=1", nil, &groups)
	if len(groups.Groups) < 10 || groups.Groups[0].Course != 1 {
		t.Errorf("groups = %+v", groups.Groups)
	}

	for path, want := range map[string]int{
		"/schedule":                       http.StatusBadRequest,
		"/schedule?date=2026-10-23":       http.StatusBadRequest,
		"/schedule?building=x":            http.StatusBadRequest,
		"/schedule?building=1&date=23.10": http.StatusBadRequest,
		"/schedule?building=9":            http.StatusNotFound,
		"/groups?building=9":              http.StatusNotFound,
	} {
		if resp := e.get(path, nil, nil); resp.StatusCode != want {
			t.Errorf("%s = %d, want %d", path, resp.StatusCode, want)
		}
	}
}

// ИСП-225ис studies in building 1 on Friday and Monday and in building 2 on
// Saturday; asking by group alone must return all three days.
func TestGroupAcrossBuildings(t *testing.T) {
	e := newEnv(t, t.TempDir())
	e.updater.Refresh(context.Background(), false)

	var resp scheduleResponse
	e.get("/schedule?group=ИСП-225ис", nil, &resp)
	got := map[string]int{}
	for _, d := range resp.Days {
		if len(d.Groups) != 1 || len(d.Groups[0].Lessons) == 0 {
			t.Fatalf("%s: groups = %+v", d.Date, d.Groups)
		}
		got[d.Date] = d.Groups[0].Lessons[0].Building
	}
	want := map[string]int{"2026-10-23": 1, "2026-10-24": 2, "2026-10-26": 1}
	if len(got) != len(want) {
		t.Fatalf("days = %v, want %v", got, want)
	}
	for date, b := range want {
		if got[date] != b {
			t.Errorf("%s building = %d, want %d", date, got[date], b)
		}
	}

	var groups struct {
		Groups []schedule.Group `json:"groups"`
	}
	e.get("/groups", nil, &groups)
	var found bool
	for _, g := range groups.Groups {
		if g.Name == "ИСП-225ис" {
			found = true
			if g.Course != 2 || len(g.Buildings) != 2 {
				t.Errorf("group = %+v", g)
			}
		}
	}
	if !found || len(groups.Groups) != 36 {
		t.Errorf("all groups: %d, found=%v", len(groups.Groups), found)
	}
}

// A snapshot written by an older parser must be re-parsed on start even
// though the PDF did not change.
func TestOldParserSnapshotIsReparsed(t *testing.T) {
	dir := t.TempDir()
	e := newEnv(t, dir)
	e.updater.Refresh(context.Background(), false)

	path := filepath.Join(dir, "spo.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var snap schedule.Snapshot
	json.Unmarshal(raw, &snap)
	snap.ParserVersion = 1
	for di := range snap.Days {
		for gi := range snap.Days[di].Groups {
			for li := range snap.Days[di].Groups[gi].Lessons {
				snap.Days[di].Groups[gi].Lessons[li].Building = 0
			}
		}
	}
	raw, _ = json.Marshal(snap)
	os.WriteFile(path, raw, 0o644)

	e2 := newEnv(t, dir)
	e2.updater.Refresh(context.Background(), false)
	if got, _ := os.ReadFile(path); !strings.Contains(string(got), `"parserVersion": 2`) {
		t.Error("old snapshot was not re-parsed")
	}
	var resp scheduleResponse
	e2.get("/schedule?group=ДО-324", nil, &resp)
	for _, d := range resp.Days {
		for _, l := range d.Groups[0].Lessons {
			if l.Building != 1 {
				t.Fatalf("%s: building = %d", d.Date, l.Building)
			}
		}
	}
}

func TestUnchangedSourceIsNotReparsed(t *testing.T) {
	e := newEnv(t, t.TempDir())
	ctx := context.Background()
	e.updater.Refresh(ctx, false)
	before := e.updater.Status("spo").LastChange
	e.updater.Refresh(ctx, false)
	if got := e.updater.Status("spo").LastChange; !got.Equal(before) {
		t.Errorf("unchanged source re-parsed: %v → %v", before, got)
	}
}

func TestOriginDownServesLastSnapshot(t *testing.T) {
	dir := t.TempDir()
	e := newEnv(t, dir)
	e.updater.Refresh(context.Background(), false)

	// Restart with the origin down: the snapshot comes from disk.
	e2 := newEnv(t, dir)
	e2.origin.failing.Store(true)
	if err := e2.updater.Refresh(context.Background(), false); err == nil {
		t.Error("expected refresh error with origin down")
	}
	var all scheduleResponse
	if resp := e2.get("/schedule?building=2", nil, &all); resp.StatusCode != http.StatusOK || len(all.Days) != 3 {
		t.Errorf("fallback = %d, %d days", resp.StatusCode, len(all.Days))
	}
	var h healthResponse
	e2.get("/health", nil, &h)
	if h.Status != "degraded" || h.Sources[0].LastError == "" {
		t.Errorf("health should report the error: %+v", h)
	}
}

func TestOverrideWins(t *testing.T) {
	dir := t.TempDir()
	e := newEnv(t, dir)
	override := `{"days":[{"date":"2026-10-23","group":"ДО-324","lessons":[{"pair":2,"start":"10:10","end":"11:40","subject":"Классный час","room":"1/1","isRemote":false}]}]}`
	if err := os.WriteFile(filepath.Join(dir, "overrides", "spo.json"), []byte(override), 0o644); err != nil {
		t.Fatal(err)
	}
	e.updater.Refresh(context.Background(), false)
	var one scheduleResponse
	e.get("/schedule?building=1&date=2026-10-23&group=ДО-324", nil, &one)
	l := one.Days[0].Groups[0].Lessons
	if len(l) != 1 || l[0].Subject != "Классный час" {
		t.Errorf("override not applied: %+v", l)
	}
}

func TestAdminRefresh(t *testing.T) {
	e := newEnv(t, t.TempDir())
	post := func(secret string) int {
		req, _ := http.NewRequest(http.MethodPost, e.server.URL+"/admin/refresh", nil)
		if secret != "" {
			req.Header.Set("X-Admin-Secret", secret)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	if got := post(""); got != http.StatusForbidden {
		t.Errorf("no secret = %d", got)
	}
	if got := post("wrong"); got != http.StatusForbidden {
		t.Errorf("wrong secret = %d", got)
	}
	e.updater.Refresh(context.Background(), false)
	gets := e.origin.gets.Load()
	if got := post("s3cret"); got != http.StatusOK {
		t.Errorf("refresh = %d", got)
	}
	if e.origin.gets.Load() != gets+2 {
		t.Error("forced refresh should download both PDFs again")
	}
}
