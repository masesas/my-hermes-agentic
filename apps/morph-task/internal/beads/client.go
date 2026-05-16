package beads

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

var ErrCommandFailed = errors.New("bd command failed")

type Client struct {
	Bin        string
	Workspace  string
	Timeout    time.Duration
	Profile    string
	extraEnv   []string
	runCommand commandRunner
}

type Result struct {
	Args     []string
	Stdout   string
	Stderr   string
	ExitCode int
}

type CommandError struct {
	Args     []string
	Stderr   string
	ExitCode int
	Profile  string
}

func (e *CommandError) Error() string {
	return fmt.Sprintf("%v: profile=%s exit=%d args=%q stderr=%q", ErrCommandFailed, e.Profile, e.ExitCode, e.Args, summarize(e.Stderr))
}

func (e *CommandError) Unwrap() error {
	return ErrCommandFailed
}

type CreateOptions struct {
	Title       string
	Description string
	Kind        string
	Target      string
}

type UpdateOptions struct {
	ID      string
	Message string
	Status  string
}

func (c Client) Create(ctx context.Context, options CreateOptions) (Result, error) {
	args := []string{"create", "--json", options.Title}
	if options.Description != "" {
		args = append(args, "--description", options.Description)
	}
	if options.Kind != "" {
		args = append(args, "--label", "kind:"+options.Kind)
	}
	if options.Target != "" {
		args = append(args, "--label", "target:"+options.Target)
	}
	return c.run(ctx, args...)
}

func (c Client) Show(ctx context.Context, id string) (Result, error) {
	return c.run(ctx, "show", "--json", id)
}

func (c Client) Ready(ctx context.Context) (Result, error) {
	return c.run(ctx, "ready", "--json")
}

func (c Client) Update(ctx context.Context, options UpdateOptions) (Result, error) {
	args := []string{"update", "--json", options.ID}
	if options.Message != "" {
		args = append(args, "--notes", options.Message)
	}
	if options.Status != "" {
		args = append(args, "--status", options.Status)
	}
	return c.run(ctx, args...)
}

func (c Client) Close(ctx context.Context, id string, reason string) (Result, error) {
	args := []string{"close", "--json", id}
	if reason != "" {
		args = append(args, "--reason", reason)
	}
	return c.run(ctx, args...)
}

func (c Client) run(ctx context.Context, args ...string) (Result, error) {
	bin := strings.TrimSpace(c.Bin)
	if bin == "" {
		bin = "bd"
	}
	timeout := c.Timeout
	if timeout <= 0 {
		timeout = 30 * time.Second
	}

	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	runner := c.runCommand
	if runner == nil {
		runner = osCommandRunner{}
	}

	result, err := runner.Run(ctx, commandSpec{
		Bin:      bin,
		Args:     append([]string(nil), args...),
		Dir:      c.Workspace,
		ExtraEnv: append([]string(nil), c.extraEnv...),
		Profile:  c.Profile,
		Timeout:  timeout,
	})
	if err != nil {
		return result, err
	}
	if result.ExitCode != 0 {
		return result, &CommandError{Args: result.Args, Stderr: result.Stderr, ExitCode: result.ExitCode, Profile: c.Profile}
	}
	return result, nil
}

type commandSpec struct {
	Bin      string
	Args     []string
	Dir      string
	ExtraEnv []string
	Profile  string
	Timeout  time.Duration
}

type commandRunner interface {
	Run(context.Context, commandSpec) (Result, error)
}

type osCommandRunner struct{}

func (osCommandRunner) Run(ctx context.Context, spec commandSpec) (Result, error) {
	cmd := exec.CommandContext(ctx, spec.Bin, spec.Args...)
	cmd.Dir = spec.Dir
	if len(spec.ExtraEnv) > 0 {
		cmd.Env = append(cmd.Environ(), spec.ExtraEnv...)
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	result := Result{
		Args:   append([]string{spec.Bin}, spec.Args...),
		Stdout: stdout.String(),
		Stderr: stderr.String(),
	}
	if cmd.ProcessState != nil {
		result.ExitCode = cmd.ProcessState.ExitCode()
	}
	if ctx.Err() != nil {
		return result, fmt.Errorf("run bd command timed out after %s: %w", spec.Timeout, ctx.Err())
	}
	if err != nil {
		if _, ok := err.(*exec.ExitError); ok {
			return result, nil
		}
		return result, fmt.Errorf("run bd command %q: %w", spec.Bin, err)
	}
	return result, nil
}

func summarize(value string) string {
	value = strings.TrimSpace(value)
	if len(value) <= 240 {
		return value
	}
	return value[:240] + "..."
}
