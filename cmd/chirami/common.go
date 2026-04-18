package main

import (
	"os"
	"os/exec"
	"path/filepath"

	"github.com/uphy/chirami/cmd/chirami/internal"
)

func openURI(subcommand string, params map[string]string) error {
	uri := internal.BuildURI(subcommand, params)
	args := []string{"-g"}

	if appPath, ok := bundledAppPath(); ok {
		args = append(args, "-a", appPath)
	}

	args = append(args, uri)
	return exec.Command("open", args...).Run()
}

func bundledAppPath() (string, bool) {
	executablePath, err := os.Executable()
	if err != nil {
		return "", false
	}

	resolvedPath, err := filepath.EvalSymlinks(executablePath)
	if err == nil {
		executablePath = resolvedPath
	}

	macosDir := filepath.Dir(executablePath)
	contentsDir := filepath.Dir(macosDir)
	appPath := filepath.Dir(contentsDir)

	if filepath.Base(macosDir) != "MacOS" || filepath.Base(contentsDir) != "Contents" || filepath.Ext(appPath) != ".app" {
		return "", false
	}

	if _, err := os.Stat(filepath.Join(appPath, "Contents", "MacOS", "Chirami")); err != nil {
		return "", false
	}

	return appPath, true
}
