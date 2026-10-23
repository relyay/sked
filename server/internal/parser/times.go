package parser

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/relya/sked/server/internal/schedule"
)

type bell struct{ start, end string }

// fillMissingTimes derives times for pages without bell times (remote
// Saturdays): the most common time of each pair on other pages of the same
// PDF, shifted for in-person pairs when the group has a "classes start at"
// note. Derived times are marked with TimeSource.
func fillMissingTimes(days []schedule.Day) {
	bells := commonBells(days)
	if len(bells) == 0 {
		return
	}
	for di := range days {
		for gi := range days[di].Groups {
			fillGroup(&days[di].Groups[gi], bells)
		}
	}
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
	t := minutes(clock) + offset
	return fmt.Sprintf("%02d:%02d", t/60, t%60)
}
