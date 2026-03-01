package internal

import (
	"bufio"
	"fmt"
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

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if strings.TrimSpace(scanner.Text()) == "CLOSED" {
			return nil
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("FIFO read error: %w", err)
	}

	// EOF without CLOSED means the writer (Chirami.app) closed without sending CLOSED,
	// which indicates a crash or unexpected termination.
	return fmt.Errorf("FIFO closed unexpectedly (Chirami.app crash?)")
}
