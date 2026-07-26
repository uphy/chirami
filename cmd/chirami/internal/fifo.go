package internal

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"syscall"
)

// CreateFIFO creates a named pipe (FIFO) in the OS temp directory.
// Returns the path to the FIFO.
func CreateFIFO() (string, error) {
	// Create a temp file to get a unique path, then replace it with a FIFO.
	f, err := os.CreateTemp("", "chirami-*.fifo")
	if err != nil {
		return "", fmt.Errorf("failed to create temp path: %w", err)
	}
	path := f.Name()
	f.Close()
	os.Remove(path)

	if err := syscall.Mkfifo(path, 0o600); err != nil {
		return "", fmt.Errorf("failed to create FIFO: %w", err)
	}
	return path, nil
}

// WaitForClosed reads from the FIFO until "CLOSED" is received.
// Returns nil on success (CLOSED received), or an error on EOF/read failure
// (e.g., Chirami.app crashed without sending CLOSED).
func WaitForClosed(pipePath string) error {
	f, err := os.Open(pipePath)
	if err != nil {
		return fmt.Errorf("failed to open FIFO: %w", err)
	}
	defer f.Close()

	for {
		line, readErr := readPipeLine(f)
		if strings.TrimSpace(line) == "CLOSED" {
			return nil
		}
		if readErr == nil {
			continue
		}
		if errors.Is(readErr, io.EOF) {
			break
		}
		return fmt.Errorf("FIFO read error: %w", readErr)
	}

	// EOF without CLOSED means the writer (Chirami.app) closed without sending CLOSED,
	// which indicates a crash or unexpected termination.
	return fmt.Errorf("FIFO closed unexpectedly (Chirami.app crash?)")
}

// ErrNoFocus is returned by WaitForContext when no Registered Note is currently focused.
var ErrNoFocus = errors.New("no focused note")

// ContextResult holds the JSON string returned by WaitForContext.
type ContextResult struct {
	JSON string
}

// WaitForContext reads from the FIFO waiting for "CONTEXT:<json>" or "NO_FOCUS".
// Returns (ContextResult, nil) on CONTEXT, or (ContextResult{}, ErrNoFocus) on NO_FOCUS.
func WaitForContext(pipePath string) (ContextResult, error) {
	f, err := os.Open(pipePath)
	if err != nil {
		return ContextResult{}, fmt.Errorf("failed to open FIFO: %w", err)
	}
	defer f.Close()

	for {
		rawLine, readErr := readPipeLine(f)
		line := strings.TrimSpace(rawLine)
		if json, ok := strings.CutPrefix(line, "CONTEXT:"); ok {
			return ContextResult{JSON: json}, nil
		}
		if line == "NO_FOCUS" {
			return ContextResult{}, ErrNoFocus
		}
		if readErr == nil {
			continue
		}
		if errors.Is(readErr, io.EOF) {
			break
		}
		return ContextResult{}, fmt.Errorf("FIFO read error: %w", readErr)
	}
	return ContextResult{}, fmt.Errorf("FIFO closed unexpectedly (Chirami.app crash?)")
}

func readPipeLine(f *os.File) (string, error) {
	return bufio.NewReader(f).ReadString('\n')
}
