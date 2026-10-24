// Package parser reconstructs the Sked schedule table from PDF geometry.
//
// Every page is one day. The page holds several horizontal blocks; each block
// starts with a "Группа:" ("Group:") row naming up to eight groups, and every group column
// is split into two subgroup columns. A lesson for the whole group is a merged
// cell, i.e. the vertical border between the subgroup columns is missing for
// that pair's rows. Text alone cannot tell the two cases apart, because Excel
// lets text overflow into empty neighbouring cells, so cells are rebuilt from
// the ruling lines and text is assigned by its origin point.
package parser

import (
	"cmp"
	"fmt"
	"math"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/relya/sked/server/internal/pdfx"
	"github.com/relya/sked/server/internal/schedule"
)

// Version identifies the parser's output shape. Bump it whenever parsing
// changes what a snapshot contains: stored snapshots with another version
// are re-parsed even if the PDF is unchanged.
const Version = 4

// Result is the parse outcome for one PDF.
type Result struct {
	Building int
	Days     []schedule.Day
	// Warnings lists every cell or page fragment the parser could not
	// interpret; they are logged and exposed via the snapshot.
	Warnings []string
}

var (
	headerRe   = regexp.MustCompile(`на\s+(\d{2})\.(\d{2})\.(\d{4})\s*г?\.?\s*\(([^)]+)\)\s*(\d)\s*КОРПУС`)
	pairTimeRe = regexp.MustCompile(`^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})$`)
	digitsRe   = regexp.MustCompile(`^\d{1,2}$`)
)

// Parse extracts all days from the pages of one schedule PDF.
func Parse(pages []pdfx.Page) Result {
	var res Result
	for _, p := range pages {
		day, warnings, ok := parsePage(p)
		for _, w := range warnings {
			res.Warnings = append(res.Warnings, fmt.Sprintf("page %d: %s", p.Number, w))
		}
		if !ok {
			continue
		}
		if res.Building == 0 {
			res.Building = day.Building
		} else if res.Building != day.Building {
			res.Warnings = append(res.Warnings, fmt.Sprintf("page %d: building %d differs from %d", p.Number, day.Building, res.Building))
		}
		res.Days = append(res.Days, day)
	}
	slices.SortFunc(res.Days, func(a, b schedule.Day) int { return cmp.Compare(a.Date, b.Date) })
	fillMissingTimes(res.Days)
	dropRedundantStartNotes(res.Days)
	return res
}

type page struct {
	pdfx.Page
	vertical   []pdfx.Segment
	horizontal []pdfx.Segment
	vlines     []float64 // clustered x positions of vertical borders
	warnings   []string
	// missingTimes counts pairs without a bell time; remote days omit them.
	missingTimes int
}

func (p *page) warn(format string, args ...any) {
	p.warnings = append(p.warnings, fmt.Sprintf(format, args...))
}

func parsePage(src pdfx.Page) (schedule.Day, []string, bool) {
	p := &page{Page: src}
	for _, s := range src.Segments {
		switch {
		case s.Vertical() && !s.Horizontal():
			if s.Y1 > s.Y2 {
				s.Y1, s.Y2 = s.Y2, s.Y1
			}
			p.vertical = append(p.vertical, s)
		case s.Horizontal() && !s.Vertical():
			if s.X1 > s.X2 {
				s.X1, s.X2 = s.X2, s.X1
			}
			p.horizontal = append(p.horizontal, s)
		}
	}
	xs := make([]float64, 0, len(p.vertical))
	for _, s := range p.vertical {
		xs = append(xs, s.X1)
	}
	p.vlines = cluster(xs, 1.5)

	var day schedule.Day
	found := false
	for _, r := range src.Runs {
		if m := headerRe.FindStringSubmatch(r.Text); m != nil {
			day.Date = m[3] + "-" + m[2] + "-" + m[1]
			day.Weekday = strings.TrimSpace(m[4])
			day.Building, _ = strconv.Atoi(m[5])
			found = true
			break
		}
	}
	if !found {
		p.warn("no date header found, page skipped")
		return day, p.warnings, false
	}

	var groupLabels []pdfx.Run
	for _, r := range src.Runs {
		if r.Text == "Группа:" {
			groupLabels = append(groupLabels, r)
		}
	}
	slices.SortFunc(groupLabels, func(a, b pdfx.Run) int { return cmp.Compare(a.Y, b.Y) })
	if len(groupLabels) == 0 {
		p.warn("no group header rows found")
		return day, p.warnings, false
	}

	byGroup := map[string]*schedule.GroupDay{}
	var order []string
	for i, label := range groupLabels {
		bottom := src.Height
		if i+1 < len(groupLabels) {
			bottom = groupLabels[i+1].Y
		}
		for _, gd := range p.parseBlock(label, bottom) {
			if existing, ok := byGroup[gd.Group]; ok {
				existing.Lessons = append(existing.Lessons, gd.Lessons...)
				existing.Notes = append(existing.Notes, gd.Notes...)
				continue
			}
			byGroup[gd.Group] = &gd
			order = append(order, gd.Group)
		}
	}
	if p.missingTimes > 0 {
		p.warn("no bell times for %d pairs, derived from the usual bell schedule", p.missingTimes)
	}
	for _, name := range order {
		gd := byGroup[name]
		slices.SortStableFunc(gd.Lessons, func(a, b schedule.Lesson) int {
			return cmp.Or(cmp.Compare(a.Pair, b.Pair), cmp.Compare(a.Subgroup, b.Subgroup))
		})
		if gd.Lessons == nil {
			gd.Lessons = []schedule.Lesson{}
		}
		for i := range gd.Lessons {
			gd.Lessons[i].Building = day.Building
		}
		day.Groups = append(day.Groups, *gd)
	}
	return day, p.warnings, true
}

type column struct {
	group       string
	x0, mid, x1 float64
}

type band struct {
	pair       int
	y0, y1     float64
	start, end string
}

// parseBlock parses the rows between a "Группа:" ("Group:") label and the next block.
func (p *page) parseBlock(label pdfx.Run, bottom float64) []schedule.GroupDay {
	var names []pdfx.Run
	for _, r := range p.Runs {
		if math.Abs(r.Y-label.Y) < 3 && r.X > label.X+30 && strings.Contains(r.Text, "-") {
			names = append(names, r)
		}
	}
	if len(names) == 0 {
		p.warn("block at y=%.0f has no group names", label.Y)
		return nil
	}
	slices.SortFunc(names, func(a, b pdfx.Run) int { return cmp.Compare(a.X, b.X) })
	tableRight := p.vlines[len(p.vlines)-1]

	cols := make([]column, len(names))
	for i, n := range names {
		cols[i] = column{group: strings.TrimSpace(n.Text), x0: p.lineAtOrLeftOf(n.X + 0.5)}
	}
	for i := range cols {
		if i+1 < len(cols) {
			cols[i].x1 = cols[i+1].x0
		} else {
			// A short last block ends at the border right of its last group
			// name, not at the table edge.
			cols[i].x1 = p.borderRightOf(names[i].X+20, label.Y-8, label.Y+3, tableRight)
		}
		// Without any subgroup border every pair of the group is a merged
		// cell, so the exact split position does not matter.
		cols[i].mid = p.lineBetween(cols[i].x0, cols[i].x1)
		if cols[i].mid == 0 {
			cols[i].mid = (cols[i].x0 + cols[i].x1) / 2
		}
	}

	bands := p.bands(label.Y, bottom, cols[0].x0)
	out := make([]schedule.GroupDay, len(cols))
	for i, c := range cols {
		out[i].Group = c.group
	}
	p.parseGrid(bands, cols, out)
	return out
}

// bands finds the pair rows of a block: pair numbers sit in the leftmost
// column, centred between the horizontal borders that delimit the pair.
func (p *page) bands(top, bottom, groupsX float64) []band {
	var digits, times []pdfx.Run
	minX := math.Inf(1)
	for _, r := range p.Runs {
		if r.Y <= top || r.Y >= bottom || r.X >= groupsX {
			continue
		}
		if digitsRe.MatchString(r.Text) {
			digits = append(digits, r)
			minX = math.Min(minX, r.X)
		} else if pairTimeRe.MatchString(r.Text) {
			times = append(times, r)
		}
	}
	var pairs []pdfx.Run
	for _, r := range digits {
		// The second digit column holds lesson ("урок") numbers.
		if r.X < minX+8 {
			pairs = append(pairs, r)
		}
	}
	probeX := minX + 2
	var ys []float64
	for _, s := range p.horizontal {
		if s.X1 <= probeX && s.X2 >= probeX {
			ys = append(ys, s.Y1)
		}
	}
	ys = cluster(ys, 1.5)

	var out []band
	for _, r := range pairs {
		n, _ := strconv.Atoi(r.Text)
		b := band{pair: n, y0: math.Inf(-1), y1: math.Inf(1)}
		for _, y := range ys {
			if y < r.Y-r.Size*0.8 && y > b.y0 {
				b.y0 = y
			}
			if y > r.Y && y < b.y1 {
				b.y1 = y
			}
		}
		if math.IsInf(b.y0, 0) || math.IsInf(b.y1, 0) {
			p.warn("pair %d at y=%.0f: row borders not found", n, r.Y)
			continue
		}
		for _, t := range times {
			if t.Y > b.y0 && t.Y < b.y1 {
				m := pairTimeRe.FindStringSubmatch(t.Text)
				b.start, b.end = clock(m[1]), clock(m[2])
			}
		}
		if b.start == "" {
			p.missingTimes++
		}
		out = append(out, b)
	}
	slices.SortFunc(out, func(a, b band) int { return cmp.Compare(a.y0, b.y0) })
	return out
}

type slot struct {
	col int
	sub schedule.Subgroup
}

// parseGrid rebuilds merged cells over the pair rows × subgroup columns grid:
// neighbours are joined wherever the border between them is missing, both
// across subgroups/groups and across consecutive pairs.
func (p *page) parseGrid(bands []band, cols []column, out []schedule.GroupDay) {
	type rect struct{ x0, x1 float64 }
	var slots []slot
	var xs []rect
	for i, c := range cols {
		slots = append(slots, slot{i, 1}, slot{i, 2})
		xs = append(xs, rect{c.x0, c.mid}, rect{c.mid, c.x1})
	}
	w := len(slots)
	parent := make([]int, len(bands)*w)
	for i := range parent {
		parent[i] = i
	}
	var find func(int) int
	find = func(i int) int {
		if parent[i] != i {
			parent[i] = find(parent[i])
		}
		return parent[i]
	}
	union := func(a, b int) { parent[find(a)] = find(b) }

	for bi, b := range bands {
		for si := 1; si < w; si++ {
			if !p.hasVerticalBorder(xs[si].x0, b.y0, b.y1) {
				union(bi*w+si-1, bi*w+si)
			}
		}
		if bi+1 < len(bands) && math.Abs(bands[bi+1].y0-b.y1) < 1.5 {
			for si := range w {
				if !p.hasHorizontalBorder(b.y1, xs[si].x0, xs[si].x1) {
					union(bi*w+si, (bi+1)*w+si)
				}
			}
		}
	}

	regions := map[int][]int{}
	var order []int
	for i := range parent {
		r := find(i)
		if _, ok := regions[r]; !ok {
			order = append(order, r)
		}
		regions[r] = append(regions[r], i)
	}

	for _, root := range order {
		members := regions[root]
		var runs []pdfx.Run
		for _, r := range p.Runs {
			for _, m := range members {
				b, x := bands[m/w], xs[m%w]
				if r.X >= x.x0-1 && r.X < x.x1-1 && r.Y > b.y0 && r.Y <= b.y1+1 {
					runs = append(runs, r)
					break
				}
			}
		}
		if len(runs) == 0 {
			continue
		}
		first := bands[members[0]/w]
		content := interpretCell(runs)
		for _, warning := range content.warnings {
			p.warn("%s pair %d: %s", cols[slots[members[0]%w].col].group, first.pair, warning)
		}

		// A cell spanning several pairs becomes one lesson with a pair range.
		type span struct{ first, last int }
		spans := map[slot]*span{}
		var targets []slot
		byBand := map[int][]slot{}
		var bandOrder []int
		for _, m := range members {
			if _, ok := byBand[m/w]; !ok {
				bandOrder = append(bandOrder, m/w)
			}
			byBand[m/w] = append(byBand[m/w], slots[m%w])
		}
		slices.Sort(bandOrder)
		for _, bi := range bandOrder {
			for _, t := range groupTargets(byBand[bi]) {
				if sp, ok := spans[t]; ok {
					sp.last = bi
					continue
				}
				spans[t] = &span{bi, bi}
				targets = append(targets, t)
			}
		}
		for _, t := range targets {
			sp := spans[t]
			first, last := bands[sp.first], bands[sp.last]
			gd := &out[t.col]
			for _, n := range content.notes {
				n.Pair = first.pair
				n.Subgroup = t.sub
				gd.Notes = append(gd.Notes, n)
			}
			if content.subject == "" {
				continue
			}
			lesson := schedule.Lesson{
				Pair:     first.pair,
				Start:    first.start,
				End:      last.end,
				Subject:  content.subject,
				Teacher:  content.teacher,
				Room:     content.room,
				IsRemote: content.remote,
				Subgroup: t.sub,
				Note:     content.note,
			}
			if sp.last != sp.first {
				lesson.PairTo = last.pair
			}
			gd.Lessons = append(gd.Lessons, lesson)
		}
	}
}

// groupTargets collapses the slots a merged cell covers: covering both
// subgroups of a group means a whole-group lesson.
func groupTargets(slots []slot) []slot {
	subs := map[int][]schedule.Subgroup{}
	var order []int
	for _, s := range slots {
		if _, ok := subs[s.col]; !ok {
			order = append(order, s.col)
		}
		subs[s.col] = append(subs[s.col], s.sub)
	}
	var out []slot
	for _, col := range order {
		if len(subs[col]) == 2 {
			out = append(out, slot{col, 0})
		} else {
			out = append(out, slot{col, subs[col][0]})
		}
	}
	return out
}

// hasVerticalBorder reports whether a border at x covers most of [y0, y1].
func (p *page) hasVerticalBorder(x, y0, y1 float64) bool {
	var spans [][2]float64
	for _, s := range p.vertical {
		if math.Abs(s.X1-x) <= 1.5 {
			spans = append(spans, [2]float64{s.Y1, s.Y2})
		}
	}
	return coverage(spans, y0, y1) >= 0.6
}

// hasHorizontalBorder reports whether a border at y covers most of [x0, x1].
func (p *page) hasHorizontalBorder(y, x0, x1 float64) bool {
	var spans [][2]float64
	for _, s := range p.horizontal {
		if math.Abs(s.Y1-y) <= 1.5 {
			spans = append(spans, [2]float64{s.X1, s.X2})
		}
	}
	return coverage(spans, x0, x1) >= 0.6
}

// coverage returns the fraction of [lo, hi] covered by the union of spans.
func coverage(spans [][2]float64, lo, hi float64) float64 {
	slices.SortFunc(spans, func(a, b [2]float64) int { return cmp.Compare(a[0], b[0]) })
	covered, end := 0.0, lo
	for _, s := range spans {
		a, b := math.Max(s[0], end), math.Min(s[1], hi)
		if b > a {
			covered += b - a
			end = b
		}
	}
	return covered / (hi - lo)
}

func (p *page) lineAtOrLeftOf(x float64) float64 {
	best := math.Inf(-1)
	for _, v := range p.vlines {
		if v <= x && v > best {
			best = v
		}
	}
	if math.IsInf(best, 0) {
		return x - 2
	}
	return best
}

// borderRightOf returns the first vertical border right of x that crosses
// the row [y0, y1], or fallback.
func (p *page) borderRightOf(x, y0, y1, fallback float64) float64 {
	for _, v := range p.vlines {
		if v > x && p.hasVerticalBorder(v, y0, y1) {
			return v
		}
	}
	return fallback
}

// lineBetween returns the border closest to the centre of (x0, x1), or 0.
func (p *page) lineBetween(x0, x1 float64) float64 {
	centre, w := (x0+x1)/2, x1-x0
	best, dist := 0.0, w*0.2
	for _, v := range p.vlines {
		if d := math.Abs(v - centre); d < dist {
			best, dist = v, d
		}
	}
	return best
}

// cluster merges values closer than tol and returns sorted representatives.
func cluster(values []float64, tol float64) []float64 {
	slices.Sort(values)
	var out []float64
	for _, v := range values {
		if len(out) > 0 && v-out[len(out)-1] <= tol {
			continue
		}
		out = append(out, v)
	}
	return out
}

// clock normalises "8:30" to "08:30".
func clock(s string) string {
	h, m, ok := strings.Cut(s, ":")
	if !ok {
		return s
	}
	if len(h) == 1 {
		h = "0" + h
	}
	return h + ":" + m
}
