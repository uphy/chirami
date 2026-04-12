package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"

	"github.com/spf13/cobra"
	"github.com/uphy/chirami/cmd/chirami/internal"
)

func init() {
	rootCmd.AddCommand(newContextCmd())
}

func newContextCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "context",
		Short: "Output context of the last focused Registered Note as JSON",
		RunE:  runContext,
	}
}

func runContext(_ *cobra.Command, _ []string) error {
	pipePath, err := internal.CreateFIFO()
	if err != nil {
		return fmt.Errorf("failed to create FIFO: %w", err)
	}
	defer os.Remove(pipePath)

	uri := internal.BuildURI("context", map[string]string{"callback_pipe": pipePath})
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
