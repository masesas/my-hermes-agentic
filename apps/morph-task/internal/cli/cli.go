package cli

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"strings"

	"github.com/morph-ai-agent/ai-agent/internal/agent"
	"github.com/morph-ai-agent/ai-agent/internal/policy"
)

const Version = "0.1.0-dev"

const (
	ExitOK          = 0
	ExitUsage       = 2
	ExitDenied      = 3
	ExitUnavailable = 4
)

type Getenv func(string) string

type Options struct {
	Args   []string
	Getenv Getenv
	Stdout io.Writer
	Stderr io.Writer
	Beads  beadsClient
	Store  runtimeStore
}

func Run(options Options) int {
	getenv := options.Getenv
	if getenv == nil {
		getenv = func(string) string { return "" }
	}
	stdout := options.Stdout
	if stdout == nil {
		stdout = io.Discard
	}
	stderr := options.Stderr
	if stderr == nil {
		stderr = io.Discard
	}

	flags := flag.NewFlagSet("morph-task", flag.ContinueOnError)
	flags.SetOutput(stderr)
	profileOverride := flags.String("profile", "", "active Morph profile; defaults to MORPH_PROFILE")
	policyPath := flags.String("policy", "", "path to role-policy.yaml; defaults to MORPH_ROLE_POLICY")
	projectOverride := flags.String("project", "", "active Morph project; defaults to MORPH_PROJECT or default")
	showVersion := flags.Bool("version", false, "print version")
	flags.Usage = func() { writeUsage(stderr) }

	if err := flags.Parse(options.Args); err != nil {
		return ExitUsage
	}
	if *showVersion {
		fmt.Fprintln(stdout, Version)
		return ExitOK
	}
	if flags.NArg() == 0 {
		writeUsage(stderr)
		return ExitUsage
	}

	request, err := parseCommand(flags.Args())
	if err != nil {
		fmt.Fprintf(stderr, "morph-task: %v\n", err)
		return ExitUsage
	}

	profile, err := agent.ResolveProfile(agent.Getenv(getenv), *profileOverride)
	if err != nil {
		fmt.Fprintf(stderr, "morph-task: %v; set MORPH_PROFILE or pass --profile\n", err)
		return ExitUsage
	}
	request.Profile = profile
	request.Project = resolveProject(getenv, *projectOverride)

	cfg, err := loadPolicy(getenv, *policyPath)
	if err != nil {
		fmt.Fprintf(stderr, "morph-task: %v\n", err)
		return ExitUnavailable
	}

	if err := cfg.Authorize(request.Request); err != nil {
		auditDenied(context.Background(), cfg, request, profile, err, options.Store, getenv)
		fmt.Fprintf(stderr, "morph-task: denied: %v\n", err)
		return ExitDenied
	}

	message, err := executeBackend(context.Background(), cfg, request, profile, options.Beads, options.Store, getenv)
	if err != nil {
		fmt.Fprintf(stderr, "morph-task: %v\n", err)
		return ExitUnavailable
	}
	fmt.Fprintln(stdout, message)
	return ExitOK
}

func resolveProject(getenv Getenv, override string) string {
	project := strings.TrimSpace(override)
	if project == "" {
		project = strings.TrimSpace(getenv("MORPH_PROJECT"))
	}
	if project == "" {
		project = strings.TrimSpace(getenv("MORPH_DEFAULT_PROJECT"))
	}
	if project == "" {
		project = "default"
	}
	return project
}

func loadPolicy(getenv Getenv, override string) (policy.Config, error) {
	path := strings.TrimSpace(override)
	if path == "" {
		path = strings.TrimSpace(getenv("MORPH_ROLE_POLICY"))
	}
	if path == "" {
		return policy.DefaultConfig(), nil
	}
	return policy.LoadFile(path)
}

func parseCommand(args []string) (commandRequest, error) {
	command := args[0]
	request := commandRequest{Request: policy.Request{Action: policy.Action(command)}}

	switch request.Action {
	case policy.ActionCreate:
		flags := newCommandFlagSet(command)
		target := flags.String("target", "", "target profile")
		kind := flags.String("kind", "", "task kind")
		title := flags.String("title", "", "task title")
		description := flags.String("description", "", "task description")
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
		request.Target = strings.TrimSpace(*target)
		request.Kind = strings.TrimSpace(*kind)
		request.Metadata.Title = strings.TrimSpace(*title)
		request.Metadata.Description = strings.TrimSpace(*description)
		if request.Target == "" {
			return commandRequest{}, errors.New("create requires --target")
		}
		if request.Kind == "" {
			return commandRequest{}, errors.New("create requires --kind")
		}
		if request.Metadata.Title == "" {
			return commandRequest{}, errors.New("create requires --title")
		}
	case policy.ActionAssign:
		flags := newCommandFlagSet(command)
		target := flags.String("target", "", "target profile")
		kind := flags.String("kind", "", "task kind")
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
		request.Target = strings.TrimSpace(*target)
		request.Kind = strings.TrimSpace(*kind)
		if flags.NArg() != 1 {
			return commandRequest{}, errors.New("assign requires bead id")
		}
		request.Metadata.BeadID = strings.TrimSpace(flags.Arg(0))
		if request.Target == "" {
			return commandRequest{}, errors.New("assign requires --target")
		}
	case policy.ActionClaim:
		flags := newCommandFlagSet(command)
		target := flags.String("target", "", "target profile")
		kind := flags.String("kind", "", "task kind")
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
		request.Target = strings.TrimSpace(*target)
		request.Kind = strings.TrimSpace(*kind)
		if flags.NArg() != 1 {
			return commandRequest{}, errors.New("claim requires bead id")
		}
		request.Metadata.BeadID = strings.TrimSpace(flags.Arg(0))
		if request.Target == "" {
			return commandRequest{}, fmt.Errorf("%s requires --target", command)
		}
	case policy.ActionProgress:
		flags := newCommandFlagSet(command)
		target := flags.String("target", "", "target profile")
		kind := flags.String("kind", "", "task kind")
		message := flags.String("message", "", "progress message")
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
		request.Target = strings.TrimSpace(*target)
		request.Kind = strings.TrimSpace(*kind)
		request.Metadata.Message = strings.TrimSpace(*message)
		if flags.NArg() != 1 {
			return commandRequest{}, errors.New("progress requires bead id")
		}
		request.Metadata.BeadID = strings.TrimSpace(flags.Arg(0))
		if request.Target == "" {
			return commandRequest{}, fmt.Errorf("%s requires --target", command)
		}
		if request.Metadata.Message == "" {
			return commandRequest{}, errors.New("progress requires --message")
		}
	case policy.ActionResult:
		flags := newCommandFlagSet(command)
		target := flags.String("target", "", "target profile")
		kind := flags.String("kind", "", "task kind")
		status := flags.String("status", "", "result status")
		message := flags.String("message", "", "result summary")
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
		request.Target = strings.TrimSpace(*target)
		request.Kind = strings.TrimSpace(*kind)
		request.Metadata.Status = strings.TrimSpace(*status)
		request.Metadata.Message = strings.TrimSpace(*message)
		if flags.NArg() != 1 {
			return commandRequest{}, errors.New("result requires bead id")
		}
		request.Metadata.BeadID = strings.TrimSpace(flags.Arg(0))
		if request.Target == "" {
			return commandRequest{}, fmt.Errorf("%s requires --target", command)
		}
		if request.Metadata.Status == "" {
			return commandRequest{}, errors.New("result requires --status")
		}
		if request.Metadata.Message == "" {
			return commandRequest{}, errors.New("result requires --message")
		}
	case policy.ActionAudit:
		flags := newCommandFlagSet(command)
		limit := flags.Int("limit", 20, "maximum audit rows")
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
		request.Metadata.Limit = *limit
	case policy.ActionHealth:
		flags := newCommandFlagSet(command)
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
	case policy.ActionReconcile:
		flags := newCommandFlagSet(command)
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
	case policy.ActionDoctor:
		flags := newCommandFlagSet(command)
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
	case policy.ActionReady:
		flags := newCommandFlagSet(command)
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
	case policy.ActionShow:
		flags := newCommandFlagSet(command)
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
		if flags.NArg() != 1 {
			return commandRequest{}, errors.New("show requires bead id")
		}
		request.Metadata.BeadID = strings.TrimSpace(flags.Arg(0))
	case policy.ActionClose:
		flags := newCommandFlagSet(command)
		reason := flags.String("reason", "", "close reason")
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
		if flags.NArg() != 1 {
			return commandRequest{}, errors.New("close requires bead id")
		}
		request.Metadata.BeadID = strings.TrimSpace(flags.Arg(0))
		request.Metadata.Message = strings.TrimSpace(*reason)
	case policy.ActionProjects:
		flags := newCommandFlagSet(command)
		if err := flags.Parse(args[1:]); err != nil {
			return commandRequest{}, err
		}
		if flags.NArg() > 0 {
			request.Metadata.BeadID = strings.TrimSpace(flags.Arg(0)) // reuse field as subcommand: "show <name>"
		}
	default:
		return commandRequest{}, fmt.Errorf("unknown command %q", command)
	}

	return request, nil
}

func newCommandFlagSet(name string) *flag.FlagSet {
	flags := flag.NewFlagSet(name, flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	return flags
}

func writeUsage(writer io.Writer) {
	fmt.Fprintf(writer, "morph-task %s\n\n", Version)
	fmt.Fprintln(writer, "Role-enforcing wrapper for Morph agent task operations.")
	fmt.Fprintln(writer, "\nUsage:")
	fmt.Fprintln(writer, "  morph-task [--profile profile] [--project project] [--policy path] <command> [flags]")
	fmt.Fprintln(writer, "\nCommands:")
	fmt.Fprintln(writer, "  create    Authorize creating a Beads-backed task")
	fmt.Fprintln(writer, "  assign    Authorize assigning a task")
	fmt.Fprintln(writer, "  ready     Authorize listing ready tasks")
	fmt.Fprintln(writer, "  show      Authorize showing a task")
	fmt.Fprintln(writer, "  claim     Authorize claiming an assigned task")
	fmt.Fprintln(writer, "  progress  Authorize appending task progress")
	fmt.Fprintln(writer, "  result    Authorize writing task result")
	fmt.Fprintln(writer, "  close     Authorize closing a task")
	fmt.Fprintln(writer, "  doctor    Validate Beads/runtime wiring")
	fmt.Fprintln(writer, "  audit     Show recent policy violations")
	fmt.Fprintln(writer, "  health    Show runtime health summary")
	fmt.Fprintln(writer, "  reconcile Compare Beads ready tasks with runtime assignments")
	fmt.Fprintln(writer, "  projects  List configured projects (optionally show <name>)")
}

func valueOrDash(value string) string {
	if value == "" {
		return "-"
	}
	return value
}
