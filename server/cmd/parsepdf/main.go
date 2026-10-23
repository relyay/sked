// Command parsepdf parses a schedule PDF and prints the result as JSON.
// It is a debugging aid for the parser; the server does not use it.
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/relya/vksit/server/internal/parser"
	"github.com/relya/vksit/server/internal/pdfx"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: parsepdf file.pdf")
		os.Exit(2)
	}
	f, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	pages, err := pdfx.Read(f, st.Size())
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	res := parser.Parse(pages)
	for _, w := range res.Warnings {
		fmt.Fprintln(os.Stderr, "warning:", w)
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	enc.Encode(res)
}
