// Integration tests that exercise the built conpty-bridge.exe as a
// subprocess. These tests cover main() — the part that unit tests on
// envInt/unbufferedCopy/min cannot reach — and confirm that ConPTY is
// actually giving us echo and interactive semantics in isolation from
// the Lisp hub and the browser.

//go:build windows

package main

import (
	"bytes"
	"io"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// buildBridge ensures the binary exists next to the source so the test
// never races against a stale copy. Uses `go build` rather than
// shelling out so the test works from any CWD go test picks.
// Build into t.TempDir so we never clash with the long-running
// conpty-bridge.exe the Lisp hub may already be holding open.
func buildBridge(t *testing.T) string {
	t.Helper()
	bin := filepath.Join(t.TempDir(), "conpty-bridge.exe")
	cmd := exec.Command("go", "build", "-o", bin, ".")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("go build failed: %v\n%s", err, out)
	}
	return bin
}

// runBridge starts the bridge and returns a helper that can write
// bytes to its stdin, read cumulative stdout bytes, and wait for exit.
type bridgeSession struct {
	t     *testing.T
	cmd   *exec.Cmd
	stdin io.WriteCloser
	mu    sync.Mutex
	buf   bytes.Buffer
}

func startBridge(t *testing.T, bin string) *bridgeSession {
	t.Helper()
	cmd := exec.Command(bin)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		t.Fatalf("StdinPipe: %v", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatalf("StdoutPipe: %v", err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	bs := &bridgeSession{t: t, cmd: cmd, stdin: stdin}
	go func() {
		buf := make([]byte, 4096)
		for {
			n, rerr := stdout.Read(buf)
			if n > 0 {
				bs.mu.Lock()
				bs.buf.Write(buf[:n])
				bs.mu.Unlock()
			}
			if rerr != nil {
				return
			}
		}
	}()
	return bs
}

func (bs *bridgeSession) send(s string) {
	bs.t.Helper()
	if _, err := bs.stdin.Write([]byte(s)); err != nil {
		bs.t.Fatalf("stdin write: %v", err)
	}
}

func (bs *bridgeSession) snapshot() string {
	bs.mu.Lock()
	defer bs.mu.Unlock()
	return bs.buf.String()
}

// stripAnsi removes ANSI CSI/OSC escape sequences so assertions can
// match against the visible text. ConPTY emits a *lot* of cursor and
// title-bar controls that otherwise drown out "is the echo there?".
func stripAnsi(s string) string {
	var out strings.Builder
	i := 0
	for i < len(s) {
		c := s[i]
		if c == 0x1b && i+1 < len(s) {
			// CSI: ESC [ ... letter  |  OSC: ESC ] ... BEL or ESC \
			next := s[i+1]
			switch next {
			case '[':
				i += 2
				for i < len(s) {
					b := s[i]
					i++
					if (b >= '@' && b <= '~') || b == 'h' || b == 'l' {
						break
					}
				}
			case ']':
				i += 2
				for i < len(s) {
					if s[i] == 7 { // BEL
						i++
						break
					}
					if s[i] == 0x1b && i+1 < len(s) && s[i+1] == '\\' {
						i += 2
						break
					}
					i++
				}
			default:
				// Unknown escape form, skip the ESC + next byte.
				i += 2
			}
			continue
		}
		out.WriteByte(c)
		i++
	}
	return out.String()
}

func (bs *bridgeSession) waitForText(substr string, d time.Duration) bool {
	bs.t.Helper()
	deadline := time.Now().Add(d)
	for time.Now().Before(deadline) {
		if strings.Contains(stripAnsi(bs.snapshot()), substr) {
			return true
		}
		time.Sleep(30 * time.Millisecond)
	}
	return false
}

func (bs *bridgeSession) close() {
	_ = bs.stdin.Close()
	// Kill unconditionally — tests shouldn't hang on cleanup.
	_ = bs.cmd.Process.Kill()
	_ = bs.cmd.Wait()
}

// --- the tests -----------------------------------------------------------

func TestBridge_BootsAndEmitsBanner(t *testing.T) {
	bin := buildBridge(t)
	bs := startBridge(t, bin)
	defer bs.close()
	if !bs.waitForText("Microsoft Windows", 3*time.Second) {
		t.Fatalf("no Windows banner within 3s. got:\n%s", stripAnsi(bs.snapshot()))
	}
}

func TestBridge_EchoesTypedCommand(t *testing.T) {
	bin := buildBridge(t)
	bs := startBridge(t, bin)
	defer bs.close()
	bs.waitForText("Microsoft Windows", 3*time.Second)
	// Simulate a user typing "whoami" then Enter. In ConPTY mode, a
	// real TTY turns the Enter key into a CR (\r) on the wire — LF
	// alone doesn't fire line processing. cmd.exe will then echo
	// every character AND run whoami, which emits the username.
	bs.send("whoami\r")
	if !bs.waitForText("whoami", 3*time.Second) {
		t.Fatalf("no echo of 'whoami' within 3s. got:\n%s", stripAnsi(bs.snapshot()))
	}
	// Require the actual command to run — echo alone is not enough
	// to prove the Enter key propagated through ConPTY.
	if !bs.waitForText("yuuji", 3*time.Second) {
		t.Fatalf("whoami did not produce 'yuuji' result within 3s. got:\n%s", stripAnsi(bs.snapshot()))
	}
}

// THE ONE THAT MATTERS:
// scripts\\pick-agent.cmd does `set /p CHOICE="> "` then branches on
// "%CHOICE%"=="1". If ConPTY is working correctly, typing `1` + Enter
// should (a) echo `1` back to stdout and (b) match the branch. If the
// bridge is forwarding input correctly, a later `claude` banner or
// command-not-found line should appear.
func TestBridge_PickAgentSetPromptEchoesDigit(t *testing.T) {
	bin := buildBridge(t)
	bs := startBridge(t, bin)
	defer bs.close()

	bs.waitForText("Microsoft Windows", 3*time.Second)

	// Invoke the picker. Path is repo-relative from tools/conpty-bridge
	// since that's our CWD (go test runs in package dir). Use CR — in
	// ConPTY mode the terminal sends CR for Enter; LF alone is just
	// a line-feed char that cmd buffers but never executes.
	bs.send("..\\..\\scripts\\pick-agent.cmd\r")
	if !bs.waitForText("pick an agent", 3*time.Second) {
		t.Fatalf("picker banner never appeared. got:\n%s", stripAnsi(bs.snapshot()))
	}
	if !bs.waitForText("> ", 2*time.Second) {
		t.Fatalf("picker prompt '> ' never appeared. got:\n%s", stripAnsi(bs.snapshot()))
	}

	// Record how much output we've seen before typing the digit so we
	// can diff afterward and see only the echo.
	before := bs.snapshot()
	bs.send("1\r")
	time.Sleep(1500 * time.Millisecond)

	delta := bs.snapshot()[len(before):]
	plain := stripAnsi(delta)

	// The critical question: does the digit echo back?
	if !strings.Contains(plain, "1") {
		t.Fatalf("typed '1' did not echo back after > prompt. delta:\n%q", plain)
	}
}
