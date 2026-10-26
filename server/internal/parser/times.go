package parser

import (
	"fmt"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/relya/sked/server/internal/schedule"
)

type bell struct{ start, end string }

// saturdayLength is how long a pair lasts on Saturdays (college rule; the
// PDFs do not print Saturday bell times).
const saturdayLength = 60

// fillMissingTimes derives times for pairs the PDF prints none for, from the
// most common time of each pair across the same PDF (the weekday grid):
//   - a page with no times at all uses the weekday grid, or on Saturdays the
//     weekday grid with 60-minute pairs (college rule);
//   - a shortened day (its printed pairs are not the usual length, e.g. 60
//     instead of 90 minutes) continues its own grid: same length, weekday
//     breaks;
//   - otherwise missing pairs get the weekday times.
//
// In-person pairs are shifted when the group has a "classes start at" note.
// Derived times are marked with TimeSource.
func fillMissingTimes(days []schedule.Day) {
	bells := commonBells(days)
	if len(bells) == 0 {
		return
	}
	usual := modeLength(bells)
	for di := range days {
		dayBells := bells
		printed := printedBells(days[di])
		switch {
		case len(printed) == 0 && isSaturday(days[di].Date):
			dayBells = shortenedGrid(bells, nil, saturdayLength)
		case len(printed) > 0 && modeLength(printed) != usual:
			dayBells = shortenedGrid(bells, printed, modeLength(printed))
		}
		for gi := range days[di].Groups {
			fillGroup(&days[di].Groups[gi], dayBells)
		}
	}
}

func isSaturday(date string) bool {
	d, err := time.Parse(time.DateOnly, date)
	return err == nil && d.Weekday() == time.Saturday
}

// printedBells is the pair grid a page prints itself.
func printedBells(day schedule.Day) map[int]bell {
	out := map[int]bell{}
	for _, g := range day.Groups {
		for _, l := range g.Lessons {
			if l.Start != "" && l.End != "" && l.PairTo == 0 && l.TimeSource == "" {
				out[l.Pair] = bell{l.Start, l.End}
			}
		}
	}
	return out
}

// modeLength is the most common pair length in minutes (shortest on ties).
func modeLength(bells map[int]bell) int {
	counts := map[int]int{}
	for _, b := range bells {
		counts[minutes(b.end)-minutes(b.start)]++
	}
	best := 0
	for length, n := range counts {
		if n > counts[best] || n == counts[best] && length < best {
			best = length
		}
	}
	return best
}

// shortenedGrid keeps the printed pairs and lays the others out after them:
// `length` minutes each, separated by the weekday breaks. A first pair with no
// printed time starts at its weekday time.
func shortenedGrid(weekday, printed map[int]bell, length int) map[int]bell {
	set := map[int]bool{}
	for p := range weekday {
		set[p] = true
	}
	for p := range printed {
		set[p] = true
	}
	pairs := make([]int, 0, len(set))
	for p := range set {
		pairs = append(pairs, p)
	}
	slices.Sort(pairs)

	out := map[int]bell{}
	for i, p := range pairs {
		if b, ok := printed[p]; ok {
			out[p] = b
			continue
		}
		var start int
		if i == 0 {
			start = minutes(weekday[p].start)
		} else {
			prev := pairs[i-1]
			breakLen := 10
			if w, ok := weekday[p]; ok {
				if wp, ok := weekday[prev]; ok {
					breakLen = max(0, minutes(w.start)-minutes(wp.end))
				}
			}
			start = minutes(out[prev].end) + breakLen
		}
		out[p] = bell{clockOf(start), clockOf(start + length)}
	}
	return out
}

func commonBells(days []schedule.Day) map[int]bell {
	counts := map[int]map[bell]int{}
	for _, d := range days {
		for _, g := range d.Groups {
			for _, l := range g.Lessons {
				if l.Start == "" || l.End == "" || l.PairTo != 0 {
					continue
				}
				if counts[l.Pair] == nil {
					counts[l.Pair] = map[bell]int{}
				}
				counts[l.Pair][bell{l.Start, l.End}]++
			}
		}
	}
	out := map[int]bell{}
	for pair, c := range counts {
		var best bell
		for b, n := range c {
			if n > c[best] || n == c[best] && b.start < best.start {
				best = b
			}
		}
		out[pair] = best
	}
	return out
}

func fillGroup(g *schedule.GroupDay, bells map[int]bell) {
	for i := range g.Lessons {
		l := &g.Lessons[i]
		if l.Start != "" {
			continue
		}
		first, ok := bells[l.Pair]
		last, okLast := bells[max(l.Pair, l.PairTo)]
		if !ok || !okLast {
			continue
		}
		l.Start, l.End, l.TimeSource = first.start, last.end, schedule.TimeFromBells
		if l.IsRemote {
			continue
		}
		startsAt := g.StartsAt(l.Subgroup)
		firstPair := firstInPersonPair(g.Lessons, l.Subgroup)
		anchor, ok := bells[firstPair]
		if startsAt == "" || !ok {
			continue
		}
		offset := minutes(startsAt) - minutes(anchor.start)
		l.Start, l.End = shift(l.Start, offset), shift(l.End, offset)
		l.TimeSource = schedule.TimeFromStartsAt
	}
}

// firstInPersonPair is the earliest non-remote pair the subgroup attends.
func firstInPersonPair(lessons []schedule.Lesson, sub schedule.Subgroup) int {
	first := 0
	for _, l := range lessons {
		if l.IsRemote || sub != 0 && l.Subgroup != 0 && l.Subgroup != sub {
			continue
		}
		if first == 0 || l.Pair < first {
			first = l.Pair
		}
	}
	return first
}

func minutes(clock string) int {
	h, m, _ := strings.Cut(clock, ":")
	hh, _ := strconv.Atoi(h)
	mm, _ := strconv.Atoi(m)
	return hh*60 + mm
}

func shift(clock string, offset int) string {
	return clockOf(minutes(clock) + offset)
}

func clockOf(t int) string {
	return fmt.Sprintf("%02d:%02d", t/60, t%60)
}

// startNoteRe matches a teacher-cell tail such as "с 8:30" ("from 8:30").
var startNoteRe = regexp.MustCompile(`^с\s*(\d{1,2}:\d{2})$`)

// dropRedundantStartNotes clears a "с 8:30" note when the lesson already
// starts at that time, so clients don't show the start twice.
func dropRedundantStartNotes(days []schedule.Day) {
	for di := range days {
		for gi := range days[di].Groups {
			lessons := days[di].Groups[gi].Lessons
			for li := range lessons {
				if m := startNoteRe.FindStringSubmatch(lessons[li].Note); m != nil && clock(m[1]) == lessons[li].Start {
					lessons[li].Note = ""
				}
			}
		}
	}
}
