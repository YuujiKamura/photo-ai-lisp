// conpty-bridge: a tiny stdin/stdout <-> ConPTY shim.
//
// Lisp's spawn-child gives a subprocess piped stdin/stdout, which means
// anything it runs (cmd.exe, and anything cmd.exe runs under it) sees no
// TTY. Interactive CLIs like `claude` detect that and refuse to start a
// REPL; `set /p` in cmd echoes nothing because it's not a real console.
//
// This bridge is a drop-in replacement for "cmd.exe" in the Lisp hub's
// argv: spawn conpty-bridge.exe, and it in turn spawns cmd.exe under a
// real Windows Pseudo Console (ConPTY). Pipe-only protocol externally,
// full terminal semantics internally.
//
//   stdin  (from Lisp) ------> ConPTY input  ------> child
//   stdout (to Lisp)   <------ ConPTY output <------ child
//
// Usage:
//   conpty-bridge.exe                    -- spawns cmd.exe
//   conpty-bridge.exe powershell.exe     -- spawns the given command
//
// Env:
//   CONPTY_COLS / CONPTY_ROWS -- initial terminal size (defaults 80x24).

package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/UserExistsError/conpty"
)

func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return def
}

// unbufferedCopy is io.Copy with a 1 KiB intermediate so small chunks
// (typing one key at a time, cmd's `set /p` echo, the prompt redraw
// after Enter) reach the other side immediately instead of sitting in
// the default 32 KiB io.Copy buffer waiting for it to fill.
func unbufferedCopy(tag string, dst io.Writer, src io.Reader) (int64, error) {
	buf := make([]byte, 1024)
	var total int64
	for {
		n, rerr := src.Read(buf)
		if n > 0 {
			if os.Getenv("CONPTY_BRIDGE_TRACE") == "1" {
				fmt.Fprintf(os.Stderr, "[bridge/%s] n=%d first=% x\n", tag, n, buf[:min(n, 16)])
			}
			w, werr := dst.Write(buf[:n])
			total += int64(w)
			if f, ok := dst.(interface{ Sync() error }); ok {
				_ = f.Sync()
			}
			if werr != nil {
				return total, werr
			}
		}
		if rerr != nil {
			if rerr == io.EOF {
				return total, nil
			}
			return total, rerr
		}
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func main() {
	cols := envInt("CONPTY_COLS", 80)
	rows := envInt("CONPTY_ROWS", 24)

	cmdline := "cmd.exe"
	if len(os.Args) > 1 {
		cmdline = strings.Join(os.Args[1:], " ")
	}

	cpty, err := conpty.Start(cmdline, conpty.ConPtyDimensions(cols, rows))
	if err != nil {
		fmt.Fprintf(os.Stderr, "conpty-bridge: Start failed: %v\n", err)
		os.Exit(1)
	}
	defer cpty.Close()

	// stdin -> ConPTY (keyboard into the child). Runs as a goroutine
	// because os.Stdin may block indefinitely; we don't want that
	// blocking our Wait on the child.
	go func() { _, _ = unbufferedCopy("in", cpty, os.Stdin) }()

	// ConPTY -> stdout (terminal output to the Lisp hub). Signal the
	// main goroutine when output EOFs so we can Wait the child AFTER
	// draining every last byte — don't os.Exit mid-write.
	outDone := make(chan struct{})
	go func() {
		_, _ = unbufferedCopy("out", os.Stdout, cpty)
		close(outDone)
	}()

	code, err := cpty.Wait(context.Background())
	if err != nil {
		fmt.Fprintf(os.Stderr, "conpty-bridge: Wait error: %v\n", err)
	}
	// Wait for the last output bytes to land on our stdout. ConPTY
	// closes its output side shortly after the child exits, which
	// EOFs our reader and closes outDone.
	<-outDone
	os.Exit(int(code))
}
