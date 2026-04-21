package main

import (
	"bytes"
	"encoding/binary"
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

// ---- resizeAwareCopy helpers -----------------------------------------------

// mockResizable records Write calls and Resize calls for assertion.
type mockResizable struct {
	written []byte
	resizes []resizeFrame
	writeErr error
}

func (m *mockResizable) Write(p []byte) (int, error) {
	if m.writeErr != nil {
		return 0, m.writeErr
	}
	m.written = append(m.written, p...)
	return len(p), nil
}

func (m *mockResizable) Resize(width, height int) error {
	m.resizes = append(m.resizes, resizeFrame{cols: uint16(width), rows: uint16(height)})
	return nil
}

// buildResizeFrame builds the 7-byte OOB frame as the Lisp side would emit.
func buildResizeFrame(cols, rows uint16) []byte {
	b := make([]byte, 7)
	b[0] = resizeMagic[0]
	b[1] = resizeMagic[1]
	b[2] = resizeMagic[2]
	binary.LittleEndian.PutUint16(b[3:5], cols)
	binary.LittleEndian.PutUint16(b[5:7], rows)
	return b
}

// ---- resizeAwareCopy tests -------------------------------------------------

// A bare resize frame with nothing else: no bytes forwarded, one Resize call.
func TestResizeAwareCopy_SingleResizeFrame(t *testing.T) {
	frame := buildResizeFrame(120, 40)
	mock := &mockResizable{}
	n, err := resizeAwareCopy("t", mock, bytes.NewReader(frame))
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if n != 0 {
		t.Fatalf("frame bytes must not be forwarded to child, got %d forwarded", n)
	}
	if len(mock.written) != 0 {
		t.Fatalf("expected no write-through, got %q", mock.written)
	}
	if len(mock.resizes) != 1 {
		t.Fatalf("expected 1 Resize call, got %d", len(mock.resizes))
	}
	if mock.resizes[0].cols != 120 || mock.resizes[0].rows != 40 {
		t.Fatalf("Resize got cols=%d rows=%d, want 120x40", mock.resizes[0].cols, mock.resizes[0].rows)
	}
}

// Normal text with no magic must pass through unchanged.
func TestResizeAwareCopy_PlainTextPassthrough(t *testing.T) {
	mock := &mockResizable{}
	text := "hello\r\nworld\r\n"
	n, err := resizeAwareCopy("t", mock, strings.NewReader(text))
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if n != int64(len(text)) {
		t.Fatalf("want %d bytes forwarded, got %d", len(text), n)
	}
	if string(mock.written) != text {
		t.Fatalf("want %q, got %q", text, mock.written)
	}
	if len(mock.resizes) != 0 {
		t.Fatalf("expected no Resize calls, got %d", len(mock.resizes))
	}
}

// Text before and after a resize frame: both parts forwarded, frame swallowed.
func TestResizeAwareCopy_TextAroundResizeFrame(t *testing.T) {
	prefix := []byte("before")
	frame := buildResizeFrame(200, 50)
	suffix := []byte("after")
	src := append(append(prefix, frame...), suffix...)

	mock := &mockResizable{}
	_, err := resizeAwareCopy("t", mock, bytes.NewReader(src))
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if string(mock.written) != "beforeafter" {
		t.Fatalf("want 'beforeafter', got %q", mock.written)
	}
	if len(mock.resizes) != 1 {
		t.Fatalf("expected 1 Resize, got %d", len(mock.resizes))
	}
	if mock.resizes[0].cols != 200 || mock.resizes[0].rows != 50 {
		t.Fatalf("Resize got cols=%d rows=%d, want 200x50", mock.resizes[0].cols, mock.resizes[0].rows)
	}
}

// Multiple resize frames in sequence: each triggers a Resize, nothing forwarded.
func TestResizeAwareCopy_MultipleResizeFrames(t *testing.T) {
	frames := append(buildResizeFrame(80, 24), buildResizeFrame(160, 48)...)
	mock := &mockResizable{}
	n, err := resizeAwareCopy("t", mock, bytes.NewReader(frames))
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if n != 0 {
		t.Fatalf("no bytes should be forwarded, got %d", n)
	}
	if len(mock.resizes) != 2 {
		t.Fatalf("expected 2 Resize calls, got %d", len(mock.resizes))
	}
	if mock.resizes[0].cols != 80 || mock.resizes[0].rows != 24 {
		t.Fatalf("first Resize: want 80x24, got %dx%d", mock.resizes[0].cols, mock.resizes[0].rows)
	}
	if mock.resizes[1].cols != 160 || mock.resizes[1].rows != 48 {
		t.Fatalf("second Resize: want 160x48, got %dx%d", mock.resizes[1].cols, mock.resizes[1].rows)
	}
}

// Partial magic (only 0x01 or 0x01 'R') must be forwarded, not swallowed.
func TestResizeAwareCopy_PartialMagicFlushed(t *testing.T) {
	// Send SOH then a byte that breaks the magic pattern ('X' != 'R').
	src := []byte{0x01, 'X', 'Y'}
	mock := &mockResizable{}
	_, err := resizeAwareCopy("t", mock, bytes.NewReader(src))
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	// All three bytes must come out unchanged.
	if string(mock.written) != "\x01XY" {
		t.Fatalf("partial magic must be flushed, got %q", mock.written)
	}
	if len(mock.resizes) != 0 {
		t.Fatalf("no Resize expected, got %d", len(mock.resizes))
	}
}

// SOH 'R' followed by a byte that isn't 'Z' — mismatch at byte 3.
func TestResizeAwareCopy_PartialMagicTwoBytesMismatch(t *testing.T) {
	src := []byte{0x01, 'R', 'X', 'Z'}
	mock := &mockResizable{}
	_, err := resizeAwareCopy("t", mock, bytes.NewReader(src))
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if string(mock.written) != "\x01RXZ" {
		t.Fatalf("partial magic mismatch must be flushed, got %q", mock.written)
	}
	if len(mock.resizes) != 0 {
		t.Fatalf("no Resize expected, got %d", len(mock.resizes))
	}
}

// u16 little-endian encoding validation: cols=0x0102 rows=0x0304.
func TestResizeAwareCopy_LittleEndianDecoding(t *testing.T) {
	// cols = 0x0102 = 258, rows = 0x0304 = 772
	frame := []byte{0x01, 'R', 'Z', 0x02, 0x01, 0x04, 0x03}
	mock := &mockResizable{}
	_, err := resizeAwareCopy("t", mock, bytes.NewReader(frame))
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(mock.resizes) != 1 {
		t.Fatalf("expected 1 Resize, got %d", len(mock.resizes))
	}
	if mock.resizes[0].cols != 258 {
		t.Fatalf("cols: want 258, got %d", mock.resizes[0].cols)
	}
	if mock.resizes[0].rows != 772 {
		t.Fatalf("rows: want 772, got %d", mock.resizes[0].rows)
	}
}
