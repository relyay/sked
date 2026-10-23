// Package source downloads schedule PDFs only when they change.
package source

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"
)

// maxSize bounds a PDF download; the real files are ~300 KB.
const maxSize = 32 << 20

// ErrNotModified reports that the source is unchanged since the last fetch.
var ErrNotModified = errors.New("source not modified")

// Document is a downloaded PDF.
type Document struct {
	Body         []byte
	SHA256       string
	ETag         string
	LastModified time.Time
}

// Fetcher remembers validators of the last successful download of one URL.
// It is not safe for concurrent use.
type Fetcher struct {
	URL    string
	Client *http.Client

	etag         string
	lastModified string
	sha          string
}

// Remember seeds the validators, e.g. from a snapshot loaded from disk, so a
// restart does not re-download an unchanged file.
func (f *Fetcher) Remember(sha string) { f.sha = sha }

// Fetch returns the document if it changed since the previous call, or
// ErrNotModified. A conditional GET is used so an unchanged file costs a 304;
// when the server ignores validators, the body hash decides.
func (f *Fetcher) Fetch(ctx context.Context) (Document, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, f.URL, nil)
	if err != nil {
		return Document{}, err
	}
	if f.etag != "" {
		req.Header.Set("If-None-Match", f.etag)
	}
	if f.lastModified != "" {
		req.Header.Set("If-Modified-Since", f.lastModified)
	}
	client := f.Client
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(req)
	if err != nil {
		return Document{}, err
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusNotModified:
		return Document{}, ErrNotModified
	case http.StatusOK:
	default:
		return Document{}, fmt.Errorf("GET %s: %s", f.URL, resp.Status)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxSize+1))
	if err != nil {
		return Document{}, fmt.Errorf("GET %s: %w", f.URL, err)
	}
	if len(body) > maxSize {
		return Document{}, fmt.Errorf("GET %s: body exceeds %d bytes", f.URL, maxSize)
	}
	if n, err := strconv.ParseInt(resp.Header.Get("Content-Length"), 10, 64); err == nil && n != int64(len(body)) {
		return Document{}, fmt.Errorf("GET %s: truncated body (%d of %d bytes)", f.URL, len(body), n)
	}
	sum := sha256.Sum256(body)
	sha := hex.EncodeToString(sum[:])

	f.etag = resp.Header.Get("ETag")
	f.lastModified = resp.Header.Get("Last-Modified")
	if sha == f.sha {
		return Document{}, ErrNotModified
	}
	f.sha = sha

	doc := Document{Body: body, SHA256: sha, ETag: f.etag}
	if t, err := http.ParseTime(f.lastModified); err == nil {
		doc.LastModified = t
	}
	return doc, nil
}

// Forget drops the validators so the next Fetch downloads the file again.
func (f *Fetcher) Forget() {
	f.etag, f.lastModified, f.sha = "", "", ""
}
