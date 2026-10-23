// Command vksitd serves the VKSIT schedule parsed from the college PDFs.
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/relya/vksit/server/internal/api"
	"github.com/relya/vksit/server/internal/source"
	"github.com/relya/vksit/server/internal/store"
	"github.com/relya/vksit/server/internal/updater"
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
	addr := flag.String("addr", env("VKSIT_ADDR", "0.0.0.0:1984"), "listen address (env VKSIT_ADDR)")
	dataDir := flag.String("data", env("VKSIT_DATA", "data"), "directory for snapshots and overrides (env VKSIT_DATA)")
	npoURL := flag.String("npo-url", env("VKSIT_NPO_URL", "https://rasp.vksit.ru/npo.pdf"), "NPO schedule PDF")
	spoURL := flag.String("spo-url", env("VKSIT_SPO_URL", "https://rasp.vksit.ru/spo.pdf"), "SPO schedule PDF")
	interval := flag.Duration("interval", 2*time.Minute, "source check interval")
	debug := flag.Bool("debug", os.Getenv("VKSIT_DEBUG") != "", "verbose logging (env VKSIT_DEBUG)")
	flag.Parse()

	level := slog.LevelInfo
	if *debug {
		level = slog.LevelDebug
	}
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))

	secret := os.Getenv("VKSIT_ADMIN_SECRET")
	if secret == "" {
		log.Warn("VKSIT_ADMIN_SECRET is empty, POST /admin/refresh is disabled")
	}

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
		Handler:           (&api.Server{Store: st, Updater: up, Version: version, AdminSecret: secret, Log: log}).Handler(),
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
