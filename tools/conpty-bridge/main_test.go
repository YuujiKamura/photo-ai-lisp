package main

import (
	"bytes"
	"errors"
	"io"
	"os"
	"strings"
	"testing"
	"time"
)

// ---- envInt --------------------------------------------------------------

func TestEnvInt_UnsetReturnsDefault(t *testing.T) {
	os.Unsetenv("TEST_ENVINT_KEY")
	if got := envInt("TEST_ENVINT_KEY", 42); got != 42 {
		t.Fatalf("want 42 (default), got %d", got)
	}
}

func TestEnvInt_ValidPositiveOverridesDefault(t *testing.T) {
	os.Setenv("TEST_ENVINT_KEY", "100")
	defer os.Unsetenv("TEST_ENVINT_KEY")
	if got := envInt("TEST_ENVINT_KEY", 42); got != 100 {
		t.Fatalf("want 100, got %d", got)
	}
}

func TestEnvInt_InvalidFallsBackToDefault(t *testing.T) {
	os.Setenv("TEST_ENVINT_KEY", "not-a-number")
	defer os.Unsetenv("TEST_ENVINT_KEY")
	if got := envInt("TEST_ENVINT_KEY", 42); got != 42 {
		t.Fatalf("bad int should fall back to default 42, got %d", got)
	}
}

func TestEnvInt_ZeroFallsBackToDefault(t *testing.T) {
	// ConPTY cols/rows of 0 is invalid, so "0" should not override.
	os.Setenv("TEST_ENVINT_KEY", "0")
	defer os.Unsetenv("TEST_ENVINT_KEY")
	if got := envInt("TEST_ENVINT_KEY", 42); got != 42 {
		t.Fatalf("0 should fall back to default 42, got %d", got)
	}
}

func TestEnvInt_NegativeFallsBackToDefault(t *testing.T) {
	os.Setenv("TEST_ENVINT_KEY", "-5")
	defer os.Unsetenv("TEST_ENVINT_KEY")
	if got := envInt("TEST_ENVINT_KEY", 42); got != 42 {
		t.Fatalf("negative should fall back to default 42, got %d", got)
	}
}

func TestEnvInt_EmptyStringFallsBackToDefault(t *testing.T) {
	os.Setenv("TEST_ENVINT_KEY", "")
	defer os.Unsetenv("TEST_ENVINT_KEY")
	if got := envInt("TEST_ENVINT_KEY", 42); got != 42 {
		t.Fatalf("empty should fall back to default 42, got %d", got)
	}
}

// ---- min ------------------------------------------------------------------

func TestMin(t *testing.T) {
	cases := []struct{ a, b, want int }{
		{1, 2, 1},
		{2, 1, 1},
		{5, 5, 5},
		{0, -1, -1},
		{-10, -5, -10},
	}
	for _, c := range cases {
		if got := min(c.a, c.b); got != c.want {
			t.Errorf("min(%d,%d)=%d, want %d", c.a, c.b, got, c.want)
		}
	}
}

// ---- unbufferedCopy -------------------------------------------------------

func TestUnbufferedCopy_CopiesAllBytes(t *testing.T) {
	src := strings.NewReader("hello world")
	var dst bytes.Buffer
	n, err := unbufferedCopy("t", &dst, src)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if n != 11 {
		t.Fatalf("want 11 bytes, got %d", n)
	}
	if got := dst.String(); got != "hello world" {
		t.Fatalf("want 'hello world', got %q", got)
	}
}

func TestUnbufferedCopy_EmptySource(t *testing.T) {
	src := strings.NewReader("")
	var dst bytes.Buffer
	n, err := unbufferedCopy("t", &dst, src)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if n != 0 {
		t.Fatalf("want 0 bytes, got %d", n)
	}
}

func TestUnbufferedCopy_HandlesLargerThanBuffer(t *testing.T) {
	// Buffer is 1024 bytes; write 5000 to exercise multiple reads.
	large := strings.Repeat("x", 5000)
	src := strings.NewReader(large)
	var dst bytes.Buffer
	n, err := unbufferedCopy("t", &dst, src)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if n != 5000 {
		t.Fatalf("want 5000 bytes, got %d", n)
	}
	if dst.Len() != 5000 {
		t.Fatalf("dst got %d bytes", dst.Len())
	}
}

// slowReader emits bytes one at a time so tests can observe per-read
// forwarding behavior (which is the whole point of unbufferedCopy).
type slowReader struct {
	data []byte
	pos  int
}

func (r *slowReader) Read(p []byte) (int, error) {
	if r.pos >= len(r.data) {
		return 0, io.EOF
	}
	p[0] = r.data[r.pos]
	r.pos++
	return 1, nil
}

func TestUnbufferedCopy_ForwardsSingleByteReads(t *testing.T) {
	src := &slowReader{data: []byte("abc")}
	var dst bytes.Buffer
	n, err := unbufferedCopy("t", &dst, src)
	if err != nil || n != 3 {
		t.Fatalf("n=%d err=%v", n, err)
	}
	if dst.String() != "abc" {
		t.Fatalf("got %q", dst.String())
	}
}

// A reader that returns n>0 AND io.EOF in the same call — perfectly
// legal per the io.Reader contract. unbufferedCopy must not lose
// those bytes.
type readerEOFWithData struct{ sent bool }

func (r *readerEOFWithData) Read(p []byte) (int, error) {
	if r.sent {
		return 0, io.EOF
	}
	copy(p, []byte("last"))
	r.sent = true
	return 4, io.EOF
}

func TestUnbufferedCopy_PreservesDataOnEOF(t *testing.T) {
	var dst bytes.Buffer
	n, err := unbufferedCopy("t", &dst, &readerEOFWithData{})
	if err != nil {
		t.Fatalf("EOF with data must be silent, got err=%v", err)
	}
	if n != 4 {
		t.Fatalf("want 4 bytes, got %d", n)
	}
	if dst.String() != "last" {
		t.Fatalf("want 'last', got %q", dst.String())
	}
}

// errReader returns a non-EOF error.
type errReader struct{}

func (errReader) Read(_ []byte) (int, error) { return 0, errors.New("boom") }

func TestUnbufferedCopy_PropagatesReadError(t *testing.T) {
	var dst bytes.Buffer
	_, err := unbufferedCopy("t", &dst, errReader{})
	if err == nil || err.Error() != "boom" {
		t.Fatalf("want 'boom' err, got %v", err)
	}
}

// errWriter always fails.
type errWriter struct{}

func (errWriter) Write(_ []byte) (int, error) { return 0, errors.New("disk full") }

func TestUnbufferedCopy_PropagatesWriteError(t *testing.T) {
	src := strings.NewReader("data")
	_, err := unbufferedCopy("t", errWriter{}, src)
	if err == nil || err.Error() != "disk full" {
		t.Fatalf("want 'disk full' err, got %v", err)
	}
}

// blockingReader blocks forever to let tests check non-timeout behavior.
type blockingReader struct{}

func (blockingReader) Read(_ []byte) (int, error) {
	select {} // park goroutine
}

func TestUnbufferedCopy_BlocksOnSlowReader(t *testing.T) {
	// Confirms that unbufferedCopy doesn't spin or return prematurely
	// when the source has nothing to give. Must be called in a goroutine
	// so the test can time-bound it.
	done := make(chan struct{})
	go func() {
		_, _ = unbufferedCopy("t", io.Discard, blockingReader{})
		close(done)
	}()
	select {
	case <-done:
		t.Fatal("unbufferedCopy returned on a never-EOF reader; it must block")
	case <-time.After(80 * time.Millisecond):
		// expected: still blocking
	}
}
