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

// fillMissingTimes derives times for pages without bell times (remote
// Saturdays) from the most common time of each pair on other pages of the
// same PDF. On Saturdays pairs last an hour, keeping the weekday first start
// and breaks. In-person pairs are shifted when the group has a "classes start
// at" note. Derived times are marked with TimeSource.
func fillMissingTimes(days []schedule.Day) {
	bells := commonBells(days)
	if len(bells) == 0 {
		return
	}
	saturday := saturdayBells(bells)
	for di := range days {
		dayBells := bells
		if date, err := time.Parse(time.DateOnly, days[di].Date); err == nil && date.Weekday() == time.Saturday {
			dayBells = saturday
		}
		for gi := range days[di].Groups {
			fillGroup(&days[di].Groups[gi], dayBells)
		}
	}
}

// saturdayBells keeps the weekday start of the first pair and the weekday
// breaks between pairs, but makes every pair saturdayLength minutes long.
func saturdayBells(weekday map[int]bell) map[int]bell {
	pairs := make([]int, 0, len(weekday))
	for p := range weekday {
		pairs = append(pairs, p)
	}
	slices.Sort(pairs)
	out := map[int]bell{}
	start := minutes(weekday[pairs[0]].start)
	for i, p := range pairs {
		if i > 0 {
			prev := pairs[i-1]
			breakLen := minutes(weekday[p].start) - minutes(weekday[prev].end)
			start = minutes(out[prev].end) + max(0, breakLen)
		}
		out[p] = bell{clockOf(start), clockOf(start + saturdayLength)}
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
