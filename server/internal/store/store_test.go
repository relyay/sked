package store

import (
	"testing"
	"time"

	"github.com/relya/sked/server/internal/schedule"
)

func days(dates ...string) []schedule.Day {
	out := make([]schedule.Day, len(dates))
	for i, d := range dates {
		out[i] = schedule.Day{Date: d, Building: 1}
	}
	return out
}

func TestUpdateKeepsRecentHistory(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 10, 26, 9, 0, 0, 0, time.UTC)
	s.Update(schedule.Snapshot{Source: "spo", Building: 1, Days: days("2026-10-01", "2026-10-23", "2026-10-24", "2026-10-26")}, now)
	// The PDF moved on: the 23rd and 24th dropped out and the 26th changed.
	next := days("2026-10-26", "2026-10-27")
	next[0].Weekday = "понедельник"
	s.Update(schedule.Snapshot{Source: "spo", Building: 1, Days: next}, now)

	reopened, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	snap := reopened.Views()[0]
	var got []string
	for _, d := range snap.Days {
		got = append(got, d.Date)
	}
	want := []string{"2026-10-23", "2026-10-24", "2026-10-26", "2026-10-27"}
	if len(got) != len(want) {
		t.Fatalf("days = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("days = %v, want %v", got, want)
		}
	}
	if snap.Days[2].Weekday != "понедельник" {
		t.Error("new data must replace stored days")
	}
}
