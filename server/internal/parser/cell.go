package parser

import (
	"cmp"
	"fmt"
	"regexp"
	"slices"
	"strings"

	"github.com/relya/sked/server/internal/pdfx"
	"github.com/relya/sked/server/internal/schedule"
)

var (
	roomRe     = regexp.MustCompile(`^(?:ауд\.?\s*)?(\d{1,3}[а-яa-z]?/\d|[А-ЯЁA-Z]{1,3}/\d|\d{1,3}\s*цех)$`)
	remoteRe   = regexp.MustCompile(`^(?i)(?:Д|\(Д\)|дистант)$`)
	teacherRe  = regexp.MustCompile(`^([А-ЯЁ][а-яё]+(?:-[А-ЯЁ][а-яё]+)?\s+[А-ЯЁ]\.\s?[А-ЯЁ]\.?)[,.]?\s*(.*)$`)
	lunchRe    = regexp.MustCompile(`^Обед\s*(?:с\s*)?(\d{1,2}:\d{2})\s*(?:-|–|до)?\s*(\d{1,2}:\d{2})?$`)
	startsAtRe = regexp.MustCompile(`^Занятия начинаются\s+с\s*(\d{1,2}:\d{2})?$`)
	clockRe    = regexp.MustCompile(`^(?:до\s+)?\d{1,2}:\d{2}$`)
)

type cellContent struct {
	subject, teacher, room, note string
	remote                       bool
	notes                        []schedule.Note
	warnings                     []string
}

// interpretCell classifies the text runs of one cell. Rooms, remote markers,
// teachers and annotations are recognised by shape; whatever remains is the
// subject.
func interpretCell(runs []pdfx.Run) cellContent {
	slices.SortFunc(runs, func(a, b pdfx.Run) int {
		if d := a.Y - b.Y; d > 2 || d < -2 {
			return cmp.Compare(a.Y, b.Y)
		}
		return cmp.Compare(a.X, b.X)
	})
	texts := joinFragments(runs)

	var c cellContent
	var subjects, teachers []string
	for _, t := range texts {
		switch {
		case remoteRe.MatchString(t):
			c.remote = true
		case roomRe.MatchString(t):
			if c.room != "" {
				c.warnings = append(c.warnings, fmt.Sprintf("second room %q ignored", t))
				continue
			}
			c.room = roomRe.FindStringSubmatch(t)[1]
		case lunchRe.MatchString(t):
			m := lunchRe.FindStringSubmatch(t)
			n := schedule.Note{Kind: schedule.NoteLunch, Text: t, Time: clock(m[1])}
			if m[2] != "" {
				n.EndTime = clock(m[2])
			}
			c.notes = append(c.notes, n)
		case startsAtRe.MatchString(t):
			m := startsAtRe.FindStringSubmatch(t)
			if m[1] == "" {
				c.warnings = append(c.warnings, fmt.Sprintf("%q without time", t))
				continue
			}
			c.notes = append(c.notes, schedule.Note{Kind: schedule.NoteStartsAt, Text: t, Time: clock(m[1])})
		case teacherRe.MatchString(t):
			m := teacherRe.FindStringSubmatch(t)
			teachers = append(teachers, m[1])
			if m[2] != "" {
				c.note = m[2]
			}
		case clockRe.MatchString(t):
			c.warnings = append(c.warnings, fmt.Sprintf("dangling time %q", t))
		default:
			subjects = append(subjects, t)
		}
	}
	c.subject = strings.Join(subjects, " ")
	c.teacher = strings.Join(teachers, ", ")
	if c.subject == "" && (c.teacher != "" || c.room != "" || c.remote) {
		c.warnings = append(c.warnings, fmt.Sprintf("cell without subject: %q", texts))
	}
	if c.remote && c.room != "" {
		c.warnings = append(c.warnings, fmt.Sprintf("remote lesson with room %q", c.room))
	}
	return c
}

// joinFragments glues annotations that Excel wrapped into several runs, e.g.
// "Обед 10:55-" + "11:20" (lunch) or "Занятия начинаются с" + "11:10"
// (classes start at).
func joinFragments(runs []pdfx.Run) []string {
	var out []string
	annotation := false
	for _, r := range runs {
		t := strings.Join(strings.Fields(r.Text), " ")
		if annotation && len(out) > 0 && isContinuation(t) {
			out[len(out)-1] += " " + t
			out[len(out)-1] = strings.ReplaceAll(out[len(out)-1], "- ", "-")
			continue
		}
		annotation = strings.HasPrefix(t, "Обед") || strings.HasPrefix(t, "Занятия начинаются") || strings.HasPrefix(t, "Собрание")
		out = append(out, t)
	}
	return out
}

func isContinuation(t string) bool {
	if clockRe.MatchString(t) {
		return true
	}
	first := []rune(t)[0]
	return first >= 'а' && first <= 'я'
}
