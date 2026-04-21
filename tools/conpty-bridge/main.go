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
//	stdin  (from Lisp) ------> ConPTY input  ------> child
//	stdout (to Lisp)   <------ ConPTY output <------ child
//
// Usage:
//
//	conpty-bridge.exe                    -- spawns cmd.exe
//	conpty-bridge.exe powershell.exe     -- spawns the given command
//
// Env:
//
//	CONPTY_COLS / CONPTY_ROWS -- initial terminal size (defaults 80x24).
//
// Resize protocol (OOB on stdin):
//
//	The bridge recognises a 7-byte magic frame embedded in the stdin stream:
//	  byte 0:   0x01  (SOH)
//	  byte 1:   'R'   (0x52)
//	  byte 2:   'Z'   (0x5A)
//	  byte 3-4: u16 cols (little-endian)
//	  byte 5-6: u16 rows (little-endian)
//
//	When detected, the bridge calls ResizePseudoConsole via cpty.Resize and
//	does NOT forward the frame bytes to the child process. All other bytes
//	pass through unchanged.
package main

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/UserExistsError/conpty"
)

// resizeMagic is the 3-byte OOB prefix that identifies a resize frame.
// SOH (0x01) + 'R' + 'Z'. These bytes cannot appear in normal user
// keyboard input because 0x01 is outside the printable ASCII range and
// the sequence is unique enough to avoid false positives from any
// terminal escape sequence prefix.
var resizeMagic = [3]byte{0x01, 'R', 'Z'}

// resizeFrame is a parsed resize request extracted from the stdin stream.
type resizeFrame struct {
	cols, rows uint16
}

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

// resizable is the interface that the ConPTY object must satisfy for
// resizeAwareCopy to issue terminal resize requests.
type resizable interface {
	io.Writer
	Resize(width, height int) error
}

// resizeAwareCopy reads from src, scanning for the 7-byte resize magic frame
// (SOH 'R' 'Z' + u16 cols LE + u16 rows LE). On detection it calls
// cpty.Resize and swallows the frame bytes; everything else is written to cpty.
//
// The scanner is byte-granular: it accumulates a 3-byte window to detect the
// magic prefix. When the window matches, it reads 4 more bytes synchronously
// and calls Resize. The window is reset after each match or mismatch flush.
//
// A partial magic prefix that is NOT followed by the remaining bytes of the
// magic is flushed to the child as-is (safe fallback).
func resizeAwareCopy(tag string, cpty resizable, src io.Reader) (int64, error) {
	// window holds bytes we have peeked but not yet forwarded (max 3 bytes
	// while we test whether the magic prefix matches).
	var window [3]byte
	windowLen := 0
	var total int64

	trace := os.Getenv("CONPTY_BRIDGE_TRACE") == "1"
	oneByte := make([]byte, 1)

	// flushWindow writes any accumulated window bytes to the child.
	flushWindow := func() error {
		if windowLen == 0 {
			return nil
		}
		if trace {
			fmt.Fprintf(os.Stderr, "[bridge/%s/flush] flushing %d window bytes\n", tag, windowLen)
		}
		n, err := cpty.Write(window[:windowLen])
		total += int64(n)
		windowLen = 0
		return err
	}

	for {
		// Read one byte at a time while scanning for magic.
		_, rerr := src.Read(oneByte)
		if rerr != nil {
			if rerr == io.EOF {
				_ = flushWindow()
				return total, nil
			}
			_ = flushWindow()
			return total, rerr
		}
		b := oneByte[0]

		if windowLen < 3 {
			// Still accumulating the potential magic prefix.
			window[windowLen] = b
			windowLen++

			// Check if the window so far matches the magic prefix up to
			// the bytes we have collected.
			match := true
			for i := 0; i < windowLen; i++ {
				if window[i] != resizeMagic[i] {
					match = false
					break
				}
			}

			if !match {
				// Mismatch: flush the window and start fresh.
				if err := flushWindow(); err != nil {
					return total, err
				}
				continue
			}

			// Window matches so far; keep accumulating (or fall through
			// once all 3 bytes are in).
			if windowLen < 3 {
				continue
			}

			// All 3 magic bytes confirmed. Read the 4 payload bytes
			// (cols u16 LE, rows u16 LE).
			var payload [4]byte
			if _, err := io.ReadFull(src, payload[:]); err != nil {
				// Can't read payload — flush what we have and propagate.
				_ = flushWindow()
				if err == io.EOF {
					return total, nil
				}
				return total, err
			}
			cols := binary.LittleEndian.Uint16(payload[0:2])
			rows := binary.LittleEndian.Uint16(payload[2:4])

			if trace {
				fmt.Fprintf(os.Stderr, "[bridge/%s/resize] cols=%d rows=%d\n", tag, cols, rows)
			}

			// Discard the magic frame — do NOT forward to child.
			windowLen = 0

			if resizeErr := cpty.Resize(int(cols), int(rows)); resizeErr != nil {
				fmt.Fprintf(os.Stderr, "conpty-bridge: Resize(%d,%d) failed: %v\n", cols, rows, resizeErr)
			}
			continue
		}

		// Normal byte — window is empty. Write directly.
		if trace {
			fmt.Fprintf(os.Stderr, "[bridge/%s] n=1 first=% x\n", tag, []byte{b})
		}
		n, werr := cpty.Write([]byte{b})
		total += int64(n)
		if werr != nil {
			return total, werr
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

	// stdin -> ConPTY (keyboard into the child). resizeAwareCopy scans
	// the incoming byte stream for the OOB resize magic frame and calls
	// ResizePseudoConsole when found; all other bytes pass through.
	go func() { _, _ = resizeAwareCopy("in", cpty, os.Stdin) }()

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
