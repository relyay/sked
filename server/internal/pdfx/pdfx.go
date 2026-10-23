// Package pdfx extracts positioned text runs and ruling lines from PDF pages.
//
// It deliberately knows nothing about schedules: it turns a page content
// stream into geometry (text origins and border segments) in a top-left
// coordinate system, which the table reconstruction in package parser uses.
package pdfx

import (
	"fmt"
	"io"
	"math"
	"strings"

	"github.com/ledongthuc/pdf"
)

// Run is the text shown by one Tj/TJ operator. X/Y is the text origin
// (baseline start), which identifies the cell the text belongs to even when
// Excel lets it overflow into neighbouring empty cells.
type Run struct {
	X, Y float64
	Size float64
	Text string
}

// Segment is a horizontal or vertical ruling line.
type Segment struct {
	X1, Y1, X2, Y2 float64
}

func (s Segment) Horizontal() bool { return math.Abs(s.Y1-s.Y2) < 0.5 }
func (s Segment) Vertical() bool   { return math.Abs(s.X1-s.X2) < 0.5 }

// Page is the extracted geometry of one page. Y grows downwards.
type Page struct {
	Number        int
	Width, Height float64
	Runs          []Run
	Segments      []Segment
}

// thinRect is the maximum thickness of a filled rectangle that is treated as
// a ruling line; Excel exports borders as hairline strokes plus thin fills.
const thinRect = 2.5

type matrix [6]float64

var identity = matrix{1, 0, 0, 1, 0, 0}

func (m matrix) mul(n matrix) matrix {
	return matrix{
		m[0]*n[0] + m[1]*n[2],
		m[0]*n[1] + m[1]*n[3],
		m[2]*n[0] + m[3]*n[2],
		m[2]*n[1] + m[3]*n[3],
		m[4]*n[0] + m[5]*n[2] + n[4],
		m[4]*n[1] + m[5]*n[3] + n[5],
	}
}

func (m matrix) apply(x, y float64) (float64, float64) {
	return x*m[0] + y*m[2] + m[4], x*m[1] + y*m[3] + m[5]
}

type gstate struct {
	ctm matrix
}

// Read extracts every page of the PDF.
func Read(r io.ReaderAt, size int64) (pages []Page, err error) {
	defer func() {
		// ledongthuc/pdf panics on malformed input; surface it as an error.
		if p := recover(); p != nil {
			err = fmt.Errorf("pdfx: malformed pdf: %v", p)
		}
	}()
	doc, err := pdf.NewReader(r, size)
	if err != nil {
		return nil, fmt.Errorf("pdfx: %w", err)
	}
	for i := 1; i <= doc.NumPage(); i++ {
		pages = append(pages, readPage(doc.Page(i), i))
	}
	return pages, nil
}

func mediaBox(p pdf.Page) pdf.Value {
	for v := p.V; !v.IsNull(); v = v.Key("Parent") {
		if box := v.Key("MediaBox"); !box.IsNull() {
			return box
		}
	}
	return pdf.Value{}
}

func readPage(p pdf.Page, number int) Page {
	box := mediaBox(p)
	page := Page{
		Number: number,
		Width:  box.Index(2).Float64() - box.Index(0).Float64(),
		Height: box.Index(3).Float64() - box.Index(1).Float64(),
	}
	contents := p.V.Key("Contents")
	if contents.IsNull() {
		return page
	}

	var (
		g       = gstate{ctm: identity}
		stack   []gstate
		tm, tlm = identity, identity
		leading float64
		enc     pdf.TextEncoding
		size    float64
		path    []Segment
		cur     [2]float64
		start   [2]float64
		rects   [][4]float64
	)
	flip := func(x, y float64) (float64, float64) {
		x, y = g.ctm.apply(x, y)
		return x, page.Height - y
	}
	show := func(adjust []float64, parts []string) {
		if enc == nil {
			return
		}
		ox, oy := tm.mul(g.ctm).apply(0, 0)
		var b strings.Builder
		for i, part := range parts {
			if i > 0 && adjust[i-1] < -250 {
				// A large negative kerning gap is how the exporter renders a space.
				b.WriteByte(' ')
			}
			b.WriteString(enc.Decode(part))
		}
		text := strings.TrimSpace(b.String())
		if text == "" {
			return
		}
		trm := tm.mul(g.ctm)
		page.Runs = append(page.Runs, Run{X: ox, Y: page.Height - oy, Size: size * math.Hypot(trm[0], trm[1]), Text: text})
	}

	pdf.Interpret(contents, func(stk *pdf.Stack, op string) {
		n := stk.Len()
		args := make([]pdf.Value, n)
		for i := n - 1; i >= 0; i-- {
			args[i] = stk.Pop()
		}
		num := func(i int) float64 { return args[i].Float64() }
		switch op {
		case "q":
			stack = append(stack, g)
		case "Q":
			if len(stack) > 0 {
				g = stack[len(stack)-1]
				stack = stack[:len(stack)-1]
			}
		case "cm":
			if n == 6 {
				g.ctm = matrix{num(0), num(1), num(2), num(3), num(4), num(5)}.mul(g.ctm)
			}
		case "BT":
			tm, tlm = identity, identity
		case "Tf":
			if n == 2 {
				font := p.Font(args[0].Name())
				enc = font.Encoder()
				size = num(1)
			}
		case "TL":
			if n == 1 {
				leading = num(0)
			}
		case "Tm":
			if n == 6 {
				tm = matrix{num(0), num(1), num(2), num(3), num(4), num(5)}
				tlm = tm
			}
		case "TD", "Td":
			if n == 2 {
				if op == "TD" {
					leading = -num(1)
				}
				tlm = matrix{1, 0, 0, 1, num(0), num(1)}.mul(tlm)
				tm = tlm
			}
		case "T*":
			tlm = matrix{1, 0, 0, 1, 0, -leading}.mul(tlm)
			tm = tlm
		case "Tj", "'", "\"":
			if n == 0 {
				return
			}
			if op != "Tj" {
				tlm = matrix{1, 0, 0, 1, 0, -leading}.mul(tlm)
				tm = tlm
			}
			s := args[n-1].RawString()
			show(nil, []string{s})
		case "TJ":
			if n != 1 {
				return
			}
			arr := args[0]
			var parts []string
			var adjust []float64
			pending := 0.0
			for i := 0; i < arr.Len(); i++ {
				v := arr.Index(i)
				if v.Kind() == pdf.String {
					if len(parts) > 0 {
						adjust = append(adjust, pending)
					}
					parts = append(parts, v.RawString())
					pending = 0
				} else {
					pending += v.Float64()
				}
			}
			show(adjust, parts)
		case "m":
			if n == 2 {
				cur = [2]float64{num(0), num(1)}
				start = cur
			}
		case "l":
			if n == 2 {
				x1, y1 := flip(cur[0], cur[1])
				x2, y2 := flip(num(0), num(1))
				path = append(path, Segment{x1, y1, x2, y2})
				cur = [2]float64{num(0), num(1)}
			}
		case "h":
			cur = start
		case "re":
			if n == 4 {
				x1, y1 := flip(num(0), num(1))
				x2, y2 := flip(num(0)+num(2), num(1)+num(3))
				rects = append(rects, [4]float64{math.Min(x1, x2), math.Min(y1, y2), math.Max(x1, x2), math.Max(y1, y2)})
			}
		case "S", "s":
			for _, s := range path {
				if s.Horizontal() || s.Vertical() {
					page.Segments = append(page.Segments, s)
				}
			}
			path, rects = nil, nil
		case "f", "F", "f*", "B", "B*", "b", "b*":
			for _, r := range rects {
				w, h := r[2]-r[0], r[3]-r[1]
				switch {
				case h <= thinRect && w > h:
					y := (r[1] + r[3]) / 2
					page.Segments = append(page.Segments, Segment{r[0], y, r[2], y})
				case w <= thinRect && h > w:
					x := (r[0] + r[2]) / 2
					page.Segments = append(page.Segments, Segment{x, r[1], x, r[3]})
				}
			}
			path, rects = nil, nil
		case "n":
			// Clipping paths are not borders.
			path, rects = nil, nil
		}
	})
	return page
}
