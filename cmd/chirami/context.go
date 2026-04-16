package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"

	"github.com/spf13/cobra"
	"github.com/uphy/chirami/cmd/chirami/internal"
)

func init() {
	rootCmd.AddCommand(newContextCmd())
}

func newContextCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "context",
		Short:   "Output context of the last focused Registered Note as JSON",
		PreRunE: validateContextFlags,
		RunE:    runContext,
	}
	cmd.Flags().Bool("transcript", false, "Include the resolved transcript block text in the JSON output")
	cmd.Flags().Int("transcript-last", 0, "Include only the last N transcript utterances")
	cmd.Flags().Int("transcript-seconds", 0, "Include only transcript utterances from the last N seconds")
	return cmd
}

func validateContextFlags(cmd *cobra.Command, _ []string) error {
	transcript, err := cmd.Flags().GetBool("transcript")
	if err != nil {
		return err
	}
	last, err := cmd.Flags().GetInt("transcript-last")
	if err != nil {
		return err
	}
	seconds, err := cmd.Flags().GetInt("transcript-seconds")
	if err != nil {
		return err
	}

	selected := 0
	if transcript {
		selected++
	}
	if cmd.Flags().Changed("transcript-last") {
		if last <= 0 {
			return fmt.Errorf("--transcript-last must be greater than 0")
		}
		selected++
	}
	if cmd.Flags().Changed("transcript-seconds") {
		if seconds <= 0 {
			return fmt.Errorf("--transcript-seconds must be greater than 0")
		}
		selected++
	}
	if selected > 1 {
		return fmt.Errorf("--transcript, --transcript-last, and --transcript-seconds are mutually exclusive")
	}
	return nil
}

func runContext(cmd *cobra.Command, _ []string) error {
	pipePath, err := internal.CreateFIFO()
	if err != nil {
		return fmt.Errorf("failed to create FIFO: %w", err)
	}
	defer os.Remove(pipePath)

	params := map[string]string{"callback_pipe": pipePath}
	transcript, err := cmd.Flags().GetBool("transcript")
	if err != nil {
		return err
	}
	last, err := cmd.Flags().GetInt("transcript-last")
	if err != nil {
		return err
	}
	seconds, err := cmd.Flags().GetInt("transcript-seconds")
	if err != nil {
		return err
	}
	switch {
	case transcript:
		params["transcript_mode"] = "full"
	case cmd.Flags().Changed("transcript-last"):
		params["transcript_mode"] = "last"
		params["transcript_value"] = strconv.Itoa(last)
	case cmd.Flags().Changed("transcript-seconds"):
		params["transcript_mode"] = "seconds"
		params["transcript_value"] = strconv.Itoa(seconds)
	}

	uri := internal.BuildURI("context", params)
	if err := exec.Command("open", "-g", uri).Run(); err != nil {
		return fmt.Errorf("failed to open chirami: %w", err)
	}

	result, err := internal.WaitForContext(pipePath)
	if err != nil {
		if errors.Is(err, internal.ErrNoFocus) {
			fmt.Fprintln(os.Stderr, "no focused note")
			os.Exit(1)
		}
		return err
	}

	fmt.Println(result.JSON)
	return nil
}
