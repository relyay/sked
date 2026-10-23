// Package schedule defines the unified schedule model served to clients.
package schedule

import (
	"slices"
	"strconv"
	"strings"
	"time"
)

// Subgroup is 1 or 2; 0 means the whole group.
type Subgroup int

// Lesson is one pair (two academic hours) for a group or one of its
// subgroups, or a run of pairs when the PDF merges them into one cell.
type Lesson struct {
	Pair int `json:"pair"`
	// Building where the pair takes place. A group can study in different
	// buildings on different days, so this is per lesson, not per student.
	Building int      `json:"building"`
	PairTo   int      `json:"pairTo,omitempty"` // last pair of a merged multi-pair cell
	Start    string   `json:"start"`            // "08:30", Europe/Moscow wall clock
	End      string   `json:"end,omitempty"`
	Subject  string   `json:"subject"`
	Teacher  string   `json:"teacher,omitempty"`
	Room     string   `json:"room,omitempty"`
	IsRemote bool     `json:"isRemote"`
	Subgroup Subgroup `json:"subgroup,omitempty"`
	Note     string   `json:"note,omitempty"`
	// TimeSource is empty when Start/End come from the PDF row. Otherwise the
	// page had no bell times and they were derived (shown as approximate).
	TimeSource TimeSource `json:"timeSource,omitempty"`
}

// TimeSource tells how a lesson time was derived when the PDF omits it.
type TimeSource string

const (
	// TimeFromBells copies the bell schedule of other days in the same PDF.
	TimeFromBells TimeSource = "bells"
	// TimeFromStartsAt shifts the bell schedule so the first in-person pair
	// starts at the "Занятия начинаются с …" time.
	TimeFromStartsAt TimeSource = "startsAt"
)

// NoteKind classifies free-text annotations found in schedule cells.
type NoteKind string

const (
	NoteStartsAt NoteKind = "startsAt"
	NoteLunch    NoteKind = "lunch"
	NoteOther    NoteKind = "other"
)

// Note is an annotation such as "Занятия начинаются с 11:10" or a lunch break.
type Note struct {
	Kind     NoteKind `json:"kind"`
	Text     string   `json:"text"`
	Time     string   `json:"time,omitempty"`    // startsAt time or lunch start
	EndTime  string   `json:"endTime,omitempty"` // lunch end
	Pair     int      `json:"pair,omitempty"`
	Subgroup Subgroup `json:"subgroup,omitempty"`
}

// GroupDay is everything one group has on one day.
type GroupDay struct {
	Group   string   `json:"group"`
	Lessons []Lesson `json:"lessons"`
	Notes   []Note   `json:"notes,omitempty"`
}

// StartsAt returns the explicit "classes start at" time for the subgroup, if any.
func (g GroupDay) StartsAt(sub Subgroup) string {
	for _, n := range g.Notes {
		if n.Kind == NoteStartsAt && (n.Subgroup == 0 || sub == 0 || n.Subgroup == sub) {
			return n.Time
		}
	}
	return ""
}

// Day is one page of the source PDF.
type Day struct {
	Date     string     `json:"date"` // YYYY-MM-DD
	Weekday  string     `json:"weekday"`
	Building int        `json:"building"`
	Groups   []GroupDay `json:"groups"`
}

// Group describes a group for onboarding.
type Group struct {
	Name   string `json:"name"`
	Course int    `json:"course"`
	// Buildings the group has classes in within the known days.
	Buildings []int `json:"buildings"`
}

// Snapshot is the parsed state of one source.
type Snapshot struct {
	Source   string    `json:"source"` // "npo" | "spo"
	Building int       `json:"building"`
	ParsedAt time.Time `json:"parsedAt"`
	// SourceModified is the Last-Modified of the PDF the newest days came from.
	SourceModified time.Time `json:"sourceModified"`
	SourceSHA256   string    `json:"sourceSha256"`
	ParserVersion  int       `json:"parserVersion"`
	Days           []Day     `json:"days"`
	Warnings       []string  `json:"warnings,omitempty"`
}

// Groups lists every group present in the snapshots, sorted by course then
// name, with all buildings each group appears in.
func Groups(snapshots ...Snapshot) []Group {
	index := map[string]int{}
	var out []Group
	for _, snap := range snapshots {
		for _, d := range snap.Days {
			for _, g := range d.Groups {
				i, ok := index[g.Group]
				if !ok {
					i = len(out)
					index[g.Group] = i
					out = append(out, Group{Name: g.Group, Course: CourseOf(g.Group)})
				}
				if !slices.Contains(out[i].Buildings, d.Building) {
					out[i].Buildings = append(out[i].Buildings, d.Building)
					slices.Sort(out[i].Buildings)
				}
			}
		}
	}
	sortGroups(out)
	return out
}

// CourseOf derives the course from the first digit of the group number:
// "ИСП-324а" → 3. It returns 0 when the name has no such digit.
func CourseOf(group string) int {
	_, num, ok := strings.Cut(group, "-")
	if !ok || num == "" {
		return 0
	}
	n, err := strconv.Atoi(num[:1])
	if err != nil {
		return 0
	}
	return n
}
