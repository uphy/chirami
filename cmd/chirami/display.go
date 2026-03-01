package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"

	"github.com/uphy/chirami/cmd/chirami/internal"

	"github.com/spf13/cobra"
)

// maxContentSize is the maximum byte size for content passed directly in the URI.
// Content larger than this is written to a tmpfile and passed via file= parameter.
// Based on practical limits of the macOS open command. (Task 0.1 result: 4096 bytes)
const maxContentSize = 4096

func newDisplayCmd() *cobra.Command {
	var fileFlag string
	var waitFlag bool
	var profileFlag string
	var idFlag string

	cmd := &cobra.Command{
		Use:   "display [text]",
		Short: "Display Markdown content in a floating window",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runDisplay(cmd, args, fileFlag, waitFlag, profileFlag, idFlag)
		},
	}

	cmd.Flags().StringVar(&fileFlag, "file", "", "Path to a Markdown file to display (editable)")
	cmd.Flags().BoolVar(&waitFlag, "wait", false, "Block until the window is closed")
	cmd.Flags().StringVar(&profileFlag, "profile", "", "Profile name for display settings")
	cmd.Flags().StringVar(&idFlag, "id", "", "Window identity for content replacement")

	return cmd
}

func runDisplay(cmd *cobra.Command, args []string, fileFlag string, waitFlag bool, profileFlag string, idFlag string) error {
	content, fileURL, isReadOnly, err := getContent(args, fileFlag)
	if err != nil {
		return err
	}

	// Task 6.9: no content available → print usage and exit 1
	if content == "" && fileURL == "" {
		fmt.Fprintln(os.Stderr, cmd.UsageString())
		return fmt.Errorf("no content provided: use [text], --file <path>, or pipe stdin")
	}

	params := map[string]string{}

	if profileFlag != "" {
		params["profile"] = profileFlag
	}
	if idFlag != "" {
		params["id"] = idFlag
	}

	if fileURL != "" {
		params["file"] = fileURL
		if isReadOnly {
			params["readonly"] = "1"
		}
	} else {
		// Task 6.5: large content → write to tmpfile, pass as file= with readonly=1
		if len(content) > maxContentSize {
			tmpFile, err := os.CreateTemp("", "chirami-*.md")
			if err != nil {
				return fmt.Errorf("failed to create temp file: %w", err)
			}
			if _, err := tmpFile.WriteString(content); err != nil {
				tmpFile.Close()
				return fmt.Errorf("failed to write temp file: %w", err)
			}
			tmpFile.Close()
			params["file"] = tmpFile.Name()
			params["readonly"] = "1"
		} else {
			params["content"] = content
		}
	}

	// Task 6.6: --wait → create FIFO and pass as callback_pipe
	var pipePath string
	if waitFlag {
		pipePath, err = internal.CreateFIFO()
		if err != nil {
			return fmt.Errorf("failed to create FIFO: %w", err)
		}
		defer os.Remove(pipePath)
		params["callback_pipe"] = pipePath
	}

	// Task 6.7: launch Chirami.app via open command
	uri := internal.BuildURI("display", params)
	if err := exec.Command("open", "-g", uri).Run(); err != nil {
		return fmt.Errorf("failed to open chirami: %w", err)
	}

	// Task 6.8: --wait → block until CLOSED received from FIFO
	if waitFlag {
		return internal.WaitForClosed(pipePath)
	}

	return nil
}

// getContent determines the display content from args, --file, or stdin.
// Priority: args > --file > stdin (Task 6.3)
func getContent(args []string, fileFlag string) (content, fileURL string, isReadOnly bool, err error) {
	// Highest priority: positional argument
	if len(args) > 0 {
		content = args[0]
		isReadOnly = true
		return
	}

	// Second priority: --file flag
	if fileFlag != "" {
		// Task 6.3.1: validate file existence
		if _, statErr := os.Stat(fileFlag); statErr != nil {
			err = fmt.Errorf("file not found: %s", fileFlag)
			return
		}
		fileURL = fileFlag
		isReadOnly = false
		return
	}

	// Third priority: stdin (only if piped, not TTY)
	// Task 6.4: distinguish TTY from pipe via ModeCharDevice
	stat, statErr := os.Stdin.Stat()
	if statErr == nil && (stat.Mode()&os.ModeCharDevice) == 0 {
		data, readErr := io.ReadAll(bufio.NewReader(os.Stdin))
		if readErr != nil {
			err = readErr
			return
		}
		content = string(data)
		isReadOnly = true
		return
	}

	// No content available
	return
}
