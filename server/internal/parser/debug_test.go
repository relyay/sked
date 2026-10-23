package parser

import (
	"fmt"
	"os"
	"strconv"
	"testing"

	"github.com/relya/vksit/server/internal/pdfx"
)

// TestDebugRegion prints runs and borders in a page region; for manual use.
func TestDebugRegion(t *testing.T) {
	spec := os.Getenv("REGION") // file:page:x0:x1:y0:y1
	if spec == "" {
		t.Skip("set REGION")
	}
	var file string
	var pg int
	var x0, x1, y0, y1 float64
	fmt.Sscanf(spec, "%s %d %f %f %f %f", &file, &pg, &x0, &x1, &y0, &y1)
	f, _ := os.Open(file)
	st, _ := f.Stat()
	pages, _ := pdfx.Read(f, st.Size())
	p := pages[pg-1]
	for _, r := range p.Runs {
		if r.X >= x0 && r.X <= x1 && r.Y >= y0 && r.Y <= y1 {
			fmt.Printf("run %6.1f %6.1f %q\n", r.X, r.Y, r.Text)
		}
	}
	for _, s := range p.Segments {
		if s.X2 >= x0 && s.X1 <= x1 && s.Y2 >= y0 && s.Y1 <= y1 || s.X1 >= x0 && s.X2 <= x1 && s.Y1 >= y0 && s.Y1 <= y1 {
			kind := "H"
			if s.Vertical() {
				kind = "V"
			}
			fmt.Println(kind, strconv.FormatFloat(s.X1, 'f', 1, 64), strconv.FormatFloat(s.Y1, 'f', 1, 64), strconv.FormatFloat(s.X2, 'f', 1, 64), strconv.FormatFloat(s.Y2, 'f', 1, 64))
		}
	}
}
