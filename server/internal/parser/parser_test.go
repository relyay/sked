package parser

import (
	"os"
	"strings"
	"testing"

	"github.com/relya/sked/server/internal/pdfx"
	"github.com/relya/sked/server/internal/schedule"
)

func parseFile(t *testing.T, name string) Result {
	t.Helper()
	f, err := os.Open("../../testdata/" + name)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		t.Fatal(err)
	}
	pages, err := pdfx.Read(f, st.Size())
	if err != nil {
		t.Fatal(err)
	}
	return Parse(pages)
}

func groupDay(t *testing.T, res Result, date, group string) schedule.GroupDay {
	t.Helper()
	for _, d := range res.Days {
		if d.Date != date {
			continue
		}
		for _, g := range d.Groups {
			if g.Group == group {
				return g
			}
		}
	}
	t.Fatalf("%s %s not found", date, group)
	return schedule.GroupDay{}
}

func lesson(t *testing.T, g schedule.GroupDay, pair int, sub schedule.Subgroup) schedule.Lesson {
	t.Helper()
	for _, l := range g.Lessons {
		if l.Pair == pair && l.Subgroup == sub {
			return l
		}
	}
	t.Fatalf("%s: no lesson for pair %d subgroup %d in %+v", g.Group, pair, sub, g.Lessons)
	return schedule.Lesson{}
}

func TestParseSPO(t *testing.T) {
	res := parseFile(t, "spo.pdf")
	if res.Building != 1 {
		t.Errorf("building = %d, want 1 (from page header)", res.Building)
	}
	var dates []string
	for _, d := range res.Days {
		dates = append(dates, d.Date)
	}
	if got, want := len(dates), 3; got != want || dates[0] != "2026-10-23" || dates[2] != "2026-10-26" {
		t.Fatalf("dates = %v", dates)
	}

	do := groupDay(t, res, "2026-10-23", "ДО-324")
	want := schedule.Lesson{Pair: 1, Building: 1, Start: "08:30", End: "10:00", Subject: "ВРпПСМ", Teacher: "Манькова Е.А.", Room: "23/1", Subgroup: 1}
	if got := lesson(t, do, 1, 1); got != want {
		t.Errorf("ДО-324 pair 1 = %+v, want %+v", got, want)
	}
	if got := lesson(t, do, 2, 2); got.Subject != "Кадровое делопроизводство" || got.Room != "24/1" || got.Teacher != "Киселева Т.В." {
		t.Errorf("wrapped subject in subgroup 2: %+v", got)
	}

	// Pair 3 of ИСП-225а is a merged cell: a whole-group lesson.
	isp := groupDay(t, res, "2026-10-23", "ИСП-225а")
	if got := lesson(t, isp, 3, 0); got.Subject != "ПОПД" || got.Room != "24/1" {
		t.Errorf("merged cell: %+v", got)
	}
	// Pair 1 only has subgroup 1; overflowing text must not leak into subgroup 2.
	for _, l := range isp.Lessons {
		if l.Pair == 1 && l.Subgroup != 1 {
			t.Errorf("unexpected pair 1 lesson %+v", l)
		}
	}
}

func TestParseRemoteAndNotes(t *testing.T) {
	res := parseFile(t, "spo.pdf")

	sat := groupDay(t, res, "2026-10-24", "ЭСС-225")
	l := lesson(t, sat, 1, 0)
	if !l.IsRemote || l.Room != "" || l.Teacher != "Коваленко В.С." || l.Subject != "ДСиКТС" {
		t.Errorf("remote lesson: %+v", l)
	}
	// The Saturday page has no bell times; derived ones must be marked.
	if l.TimeSource == "" {
		t.Errorf("derived time %q-%q not marked", l.Start, l.End)
	}

	sis := groupDay(t, res, "2026-10-24", "СИС-126")
	if got := sis.StartsAt(0); got != "11:10" {
		t.Errorf("startsAt = %q, want 11:10", got)
	}

	do := groupDay(t, res, "2026-10-23", "ДО-324")
	var lunch *schedule.Note
	for i, n := range do.Notes {
		if n.Kind == schedule.NoteLunch {
			lunch = &do.Notes[i]
		}
	}
	if lunch == nil || lunch.Time != "10:55" || lunch.EndTime != "11:20" || lunch.Subgroup != 1 {
		t.Errorf("split lunch note not joined: %+v", do.Notes)
	}
}

// The exam cell says "с 8:30" ("from 8:30") after the teacher; it equals the
// start of pair 1, so it must not be repeated as a note.
func TestParseMergedAcrossPairs(t *testing.T) {
	res := parseFile(t, "spo.pdf")
	g := groupDay(t, res, "2026-10-26", "ЭСС-225")
	if len(g.Lessons) != 1 {
		t.Fatalf("lessons = %+v, want one merged exam", g.Lessons)
	}
	l := g.Lessons[0]
	if l.Subject != `Экзамен "Электротехника"` || l.Teacher != "Андрианов Н.В." || l.Room != "114/1" ||
		l.Pair != 1 || l.PairTo != 6 || l.Start != "08:30" || l.End != "18:50" || l.Note != "" {
		t.Errorf("exam = %+v", l)
	}
}

func TestParseNPO(t *testing.T) {
	res := parseFile(t, "npo.pdf")
	if res.Building != 2 {
		t.Errorf("building = %d, want 2", res.Building)
	}
	g := groupDay(t, res, "2026-10-23", "РУПО-126б")
	if got := lesson(t, g, 2, 1); got.Subject != "Информатика" || got.Start != "10:40" || got.End != "12:40" {
		t.Errorf("npo subgroup lesson: %+v", got)
	}
	if got := lesson(t, g, 2, 2); got.Subject != "Физика" || got.Room != "3/2" {
		t.Errorf("npo subgroup 2: %+v", got)
	}
	ru := groupDay(t, res, "2026-10-23", "РУПО-126ис")
	if got := lesson(t, ru, 4, 0); got.Room != "11 цех" {
		t.Errorf("workshop room: %+v", got)
	}
}

func TestNoUnrecognisedCells(t *testing.T) {
	for _, name := range []string{"npo.pdf", "spo.pdf"} {
		res := parseFile(t, name)
		for _, w := range res.Warnings {
			// Missing bell times on remote Saturdays are expected.
			if !strings.Contains(w, "no bell times") {
				t.Errorf("%s: %s", name, w)
			}
		}
	}
}

func TestMissingTimesAreDerived(t *testing.T) {
	// Saturday 24.10 has no bell times. Pairs last an hour on Saturdays, with
	// the weekday first start and breaks.
	spo := parseFile(t, "spo.pdf")
	sat := groupDay(t, spo, "2026-10-24", "ЭСС-225")
	for pair, want := range map[int][2]string{1: {"08:30", "09:30"}, 2: {"09:40", "10:40"}, 3: {"11:10", "12:10"}, 4: {"12:20", "13:20"}} {
		l := lesson(t, sat, pair, 0)
		if l.Start != want[0] || l.End != want[1] || l.TimeSource != schedule.TimeFromBells {
			t.Errorf("spo saturday pair %d = %s–%s (%s), want %s–%s", pair, l.Start, l.End, l.TimeSource, want[0], want[1])
		}
	}

	// In-person PE after remote pairs, with "Занятия начинаются с 11:50"
	// ("classes start at 11:50"): the Saturday grid (pair 3 = 11:20) is
	// shifted to start at 11:50.
	npo := parseFile(t, "npo.pdf")
	g := groupDay(t, npo, "2026-10-24", "ИСП-225ис")
	if l := lesson(t, g, 1, 0); l.Start != "09:00" || l.End != "10:00" || l.TimeSource != schedule.TimeFromBells {
		t.Errorf("remote pair 1 = %+v", l)
	}
	if l := lesson(t, g, 3, 0); l.Start != "11:50" || l.End != "12:50" || l.TimeSource != schedule.TimeFromStartsAt {
		t.Errorf("in-person pair 3 = %+v", l)
	}
	if l := lesson(t, g, 4, 0); l.Start != "13:00" || l.End != "14:00" || l.TimeSource != schedule.TimeFromStartsAt {
		t.Errorf("in-person pair 4 = %+v", l)
	}

	// Times present in the PDF are never marked.
	if l := lesson(t, groupDay(t, spo, "2026-10-23", "ДО-324"), 1, 1); l.TimeSource != "" {
		t.Errorf("pdf time marked as derived: %+v", l)
	}
}
