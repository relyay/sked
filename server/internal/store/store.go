// Package store keeps the latest good snapshot of every source in memory and
// on disk, and applies manual overrides on top of parsed data.
package store

import (
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"time"

	"github.com/relya/vksit/server/internal/schedule"
)

// historyDays is how long days that dropped out of the PDF stay available.
const historyDays = 14

// Store is safe for concurrent use.
type Store struct {
	dir string

	mu        sync.RWMutex
	snapshots map[string]schedule.Snapshot // by source name
	overrides map[string]Overrides
}

// Overrides replace parsed group days. The file overrides/<source>.json is
// written by hand and wins over the parser.
type Overrides struct {
	Days []OverrideDay `json:"days"`
}

// OverrideDay replaces one group's day entirely; empty Lessons means "no
// classes".
type OverrideDay struct {
	Date    string            `json:"date"`
	Group   string            `json:"group"`
	Lessons []schedule.Lesson `json:"lessons"`
	Notes   []schedule.Note   `json:"notes,omitempty"`
}

// Open loads snapshots and overrides from dir, creating it if needed.
func Open(dir string) (*Store, error) {
	if err := os.MkdirAll(filepath.Join(dir, "overrides"), 0o755); err != nil {
		return nil, err
	}
	s := &Store{dir: dir, snapshots: map[string]schedule.Snapshot{}, overrides: map[string]Overrides{}}
	files, err := filepath.Glob(filepath.Join(dir, "*.json"))
	if err != nil {
		return nil, err
	}
	for _, path := range files {
		var snap schedule.Snapshot
		if err := readJSON(path, &snap); err != nil {
			return nil, fmt.Errorf("store: %s: %w", path, err)
		}
		s.snapshots[snap.Source] = snap
	}
	return s, nil
}

// Snapshot returns the stored snapshot of a source without overrides.
func (s *Store) Snapshot(source string) (schedule.Snapshot, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	snap, ok := s.snapshots[source]
	return snap, ok
}

// Views returns every snapshot with overrides applied, ordered by building.
func (s *Store) Views() []schedule.Snapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var out []schedule.Snapshot
	for _, snap := range s.snapshots {
		out = append(out, applyOverrides(snap, s.overrides[snap.Source]))
	}
	slices.SortFunc(out, func(a, b schedule.Snapshot) int { return cmp.Compare(a.Building, b.Building) })
	return out
}

// Buildings lists the known building numbers in ascending order.
func (s *Store) Buildings() []schedule.Snapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var out []schedule.Snapshot
	for _, snap := range s.snapshots {
		snap.Days = nil
		out = append(out, snap)
	}
	slices.SortFunc(out, func(a, b schedule.Snapshot) int { return cmp.Compare(a.Building, b.Building) })
	return out
}

// Update merges a freshly parsed snapshot with history and persists it.
// Days present in next replace stored ones; earlier days are kept for
// historyDays so the client can still show a day after the PDF moved on.
func (s *Store) Update(next schedule.Snapshot, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if prev, ok := s.snapshots[next.Source]; ok && len(next.Days) > 0 {
		first := next.Days[0].Date
		cutoff := now.AddDate(0, 0, -historyDays).Format(time.DateOnly)
		var kept []schedule.Day
		for _, d := range prev.Days {
			if d.Date < first && d.Date >= cutoff {
				kept = append(kept, d)
			}
		}
		next.Days = append(kept, next.Days...)
	}
	if err := writeJSON(filepath.Join(s.dir, next.Source+".json"), next); err != nil {
		return err
	}
	s.snapshots[next.Source] = next
	return nil
}

// ReloadOverrides rereads overrides/<source>.json for every source.
func (s *Store) ReloadOverrides(sources []string) error {
	loaded := map[string]Overrides{}
	var errs []error
	for _, src := range sources {
		var o Overrides
		err := readJSON(filepath.Join(s.dir, "overrides", src+".json"), &o)
		switch {
		case errors.Is(err, fs.ErrNotExist):
		case err != nil:
			errs = append(errs, fmt.Errorf("overrides %s: %w", src, err))
			// Keep serving the previous overrides rather than silently dropping them.
			s.mu.RLock()
			loaded[src] = s.overrides[src]
			s.mu.RUnlock()
		default:
			loaded[src] = o
		}
	}
	s.mu.Lock()
	s.overrides = loaded
	s.mu.Unlock()
	return errors.Join(errs...)
}

func applyOverrides(snap schedule.Snapshot, o Overrides) schedule.Snapshot {
	if len(o.Days) == 0 {
		return snap
	}
	days := slices.Clone(snap.Days)
	for _, od := range o.Days {
		lessons := slices.Clone(od.Lessons)
		if lessons == nil {
			lessons = []schedule.Lesson{}
		}
		for i := range lessons {
			if lessons[i].Building == 0 {
				lessons[i].Building = snap.Building
			}
		}
		gd := schedule.GroupDay{Group: od.Group, Lessons: lessons, Notes: od.Notes}
		i := slices.IndexFunc(days, func(d schedule.Day) bool { return d.Date == od.Date })
		if i < 0 {
			days = append(days, schedule.Day{Date: od.Date, Building: snap.Building})
			i = len(days) - 1
		}
		groups := slices.Clone(days[i].Groups)
		if j := slices.IndexFunc(groups, func(g schedule.GroupDay) bool { return g.Group == od.Group }); j >= 0 {
			groups[j] = gd
		} else {
			groups = append(groups, gd)
		}
		days[i].Groups = groups
	}
	slices.SortFunc(days, func(a, b schedule.Day) int { return cmp.Compare(a.Date, b.Date) })
	snap.Days = days
	return snap
}

func readJSON(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

// writeJSON replaces path atomically so a crash never leaves a torn snapshot.
func writeJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".snapshot-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
