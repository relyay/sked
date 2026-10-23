// Command skedd serves the Sked schedule parsed from the college PDFs.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/relya/sked/server/internal/api"
	"github.com/relya/sked/server/internal/source"
	"github.com/relya/sked/server/internal/store"
	"github.com/relya/sked/server/internal/updater"
)

// version is set at build time: -ldflags "-X main.version=1.0.0".
var version = "dev"

func env(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok {
		return v
	}
	return fallback
}

func main() {
	addr := flag.String("addr", env("SKED_ADDR", "0.0.0.0:1984"), "listen address (env SKED_ADDR)")
	dataDir := flag.String("data", env("SKED_DATA", "data"), "directory for snapshots and overrides (env SKED_DATA)")
	npoURL := flag.String("npo-url", env("SKED_NPO_URL", "https://rasp.vksit.ru/npo.pdf"), "NPO schedule PDF")
	spoURL := flag.String("spo-url", env("SKED_SPO_URL", "https://rasp.vksit.ru/spo.pdf"), "SPO schedule PDF")
	interval := flag.Duration("interval", 2*time.Minute, "source check interval")
	debug := flag.Bool("debug", os.Getenv("SKED_DEBUG") != "", "verbose logging (env SKED_DEBUG)")
	healthcheck := flag.Bool("healthcheck", false, "query /health of the server at -addr and exit 0 if it answers (for container health checks)")
	flag.Parse()

	if *healthcheck {
		os.Exit(checkHealth(*addr))
	}

	level := slog.LevelInfo
	if *debug {
		level = slog.LevelDebug
	}
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))

	st, err := store.Open(*dataDir)
	if err != nil {
		log.Error("open store", "err", err)
		os.Exit(1)
	}
	client := &http.Client{Timeout: 45 * time.Second}
	up := updater.New([]updater.Source{
		{Name: "npo", Fetcher: &source.Fetcher{URL: *npoURL, Client: client}},
		{Name: "spo", Fetcher: &source.Fetcher{URL: *spoURL, Client: client}},
	}, st, log)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go up.Run(ctx, *interval)

	srv := &http.Server{
		Addr:              *addr,
		Handler:           (&api.Server{Store: st, Updater: up, Version: version, Log: log}).Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       2 * time.Minute,
	}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(shutdown)
	}()
	log.Info("listening", "addr", *addr, "version", version)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Error("listen", "err", err)
		os.Exit(1)
	}
}

// checkHealth is the container health probe: the runtime image has no shell
// or curl, so the binary checks itself.
func checkHealth(addr string) int {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		fmt.Fprintln(os.Stderr, "healthcheck:", err)
		return 1
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://" + net.JoinHostPort(host, port) + "/health")
	if err != nil {
		fmt.Fprintln(os.Stderr, "healthcheck:", err)
		return 1
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Fprintln(os.Stderr, "healthcheck:", resp.Status)
		return 1
	}
	return 0
}
