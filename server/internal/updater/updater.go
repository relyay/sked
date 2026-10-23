// Package updater polls the schedule PDFs and feeds parsed snapshots to the
// store.
package updater

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"

	"github.com/relya/sked/server/internal/parser"
	"github.com/relya/sked/server/internal/pdfx"
	"github.com/relya/sked/server/internal/schedule"
	"github.com/relya/sked/server/internal/source"
	"github.com/relya/sked/server/internal/store"
)

// Source is one schedule PDF.
type Source struct {
	Name    string // "npo" | "spo"
	Fetcher *source.Fetcher
}

// Status is what /health reports per source.
type Status struct {
	Source      string    `json:"source"`
	Building    int       `json:"building,omitempty"`
	LastCheck   time.Time `json:"lastCheck,omitzero"`
	LastSuccess time.Time `json:"lastSuccess,omitzero"` // last successful parse
	LastChange  time.Time `json:"lastChange,omitzero"`
	LastError   string    `json:"lastError,omitempty"`
	Days        int       `json:"days"`
	Warnings    int       `json:"warnings"`
}

// Updater serialises refreshes; Refresh may be called concurrently with Run.
type Updater struct {
	Sources []Source
	Store   *store.Store
	Log     *slog.Logger
	Now     func() time.Time

	refresh sync.Mutex
	mu      sync.RWMutex
	status  map[string]Status
}

// New seeds fetchers from stored snapshots so restarts skip unchanged files.
func New(sources []Source, st *store.Store, log *slog.Logger) *Updater {
	u := &Updater{Sources: sources, Store: st, Log: log, Now: time.Now, status: map[string]Status{}}
	for _, src := range sources {
		s := Status{Source: src.Name}
		if snap, ok := st.Snapshot(src.Name); ok {
			// A snapshot from an older parser is re-parsed from the same PDF.
			if snap.ParserVersion == parser.Version {
				src.Fetcher.Remember(snap.SourceSHA256)
			}
			s.Building, s.LastSuccess, s.LastChange = snap.Building, snap.ParsedAt, snap.ParsedAt
			s.Days, s.Warnings = len(snap.Days), len(snap.Warnings)
		}
		u.status[src.Name] = s
	}
	return u
}

// Run refreshes immediately and then every interval until ctx is done.
func (u *Updater) Run(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		u.Refresh(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// Refresh checks every source and returns the joined per-source errors.
func (u *Updater) Refresh(ctx context.Context) error {
	u.refresh.Lock()
	defer u.refresh.Unlock()

	names := make([]string, len(u.Sources))
	for i, s := range u.Sources {
		names[i] = s.Name
	}
	var errs []error
	if err := u.Store.ReloadOverrides(names); err != nil {
		u.Log.Error("overrides", "err", err)
		errs = append(errs, err)
	}
	for _, src := range u.Sources {
		if err := u.refreshSource(ctx, src); err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

func (u *Updater) refreshSource(ctx context.Context, src Source) error {
	log := u.Log.With("source", src.Name)
	now := u.Now()
	st := u.Status(src.Name)
	st.LastCheck = now
	defer func() { u.setStatus(st) }()

	fetchCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	doc, err := src.Fetcher.Fetch(fetchCtx)
	switch {
	case errors.Is(err, source.ErrNotModified):
		log.Debug("source unchanged")
		st.LastError = ""
		return nil
	case err != nil:
		log.Warn("source error, serving last snapshot", "err", err)
		st.LastError = err.Error()
		return err
	}
	log.Info("source changed", "sha256", doc.SHA256, "lastModified", doc.LastModified, "bytes", len(doc.Body))

	pages, err := pdfx.Read(bytes.NewReader(doc.Body), int64(len(doc.Body)))
	if err == nil && len(pages) == 0 {
		err = errors.New("pdf has no pages")
	}
	var res parser.Result
	if err == nil {
		res = parser.Parse(pages)
		if len(res.Days) == 0 {
			err = errors.New("no days recognised")
		}
	}
	if err != nil {
		// Retry the same bytes next tick instead of treating them as known.
		src.Fetcher.Forget()
		log.Error("parse failed, keeping last snapshot", "err", err)
		st.LastError = "parse: " + err.Error()
		return err
	}
	for _, w := range res.Warnings {
		log.Warn("parser warning", "detail", w)
	}

	snap := schedule.Snapshot{
		Source:         src.Name,
		Building:       res.Building,
		ParsedAt:       now,
		SourceModified: doc.LastModified,
		SourceSHA256:   doc.SHA256,
		ParserVersion:  parser.Version,
		Days:           res.Days,
		Warnings:       res.Warnings,
	}
	if err := u.Store.Update(snap, now); err != nil {
		log.Error("persist snapshot", "err", err)
		st.LastError = "store: " + err.Error()
		return err
	}
	log.Info("parsed", "building", res.Building, "days", len(res.Days), "warnings", len(res.Warnings))
	st.Building, st.LastSuccess, st.LastChange, st.LastError = res.Building, now, now, ""
	st.Days, st.Warnings = len(res.Days), len(res.Warnings)
	return nil
}

// Status returns the current status of a source.
func (u *Updater) Status(name string) Status {
	u.mu.RLock()
	defer u.mu.RUnlock()
	return u.status[name]
}

// Statuses returns all statuses in source order.
func (u *Updater) Statuses() []Status {
	u.mu.RLock()
	defer u.mu.RUnlock()
	out := make([]Status, 0, len(u.Sources))
	for _, s := range u.Sources {
		out = append(out, u.status[s.Name])
	}
	return out
}

func (u *Updater) setStatus(s Status) {
	u.mu.Lock()
	defer u.mu.Unlock()
	u.status[s.Source] = s
}
