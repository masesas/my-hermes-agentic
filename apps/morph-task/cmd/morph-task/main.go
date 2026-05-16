package main

import (
	"os"

	"github.com/morph-ai-agent/ai-agent/internal/cli"
)

func main() {
	os.Exit(cli.Run(cli.Options{
		Args:   os.Args[1:],
		Getenv: os.Getenv,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}))
}
