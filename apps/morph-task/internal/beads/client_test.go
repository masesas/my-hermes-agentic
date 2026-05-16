package beads

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"
)

func TestCreateBuildsTypedArgs(t *testing.T) {
	runner := &fakeRunner{result: Result{Stdout: `{"id":"task-1"}`}}
	client := Client{
		Bin:        "/opt/morph-agency/bin/bd",
		Workspace:  "/home/hermes/workspace",
		Timeout:    5 * time.Second,
		Profile:    "orchestrator",
		runCommand: runner,
	}

	result, err := client.Create(context.Background(), CreateOptions{
		Title:       "Implement policy engine",
		Description: "Add role checks",
		Kind:        "execution",
		Target:      "executor",
	})
	if err != nil {
		t.Fatalf("Create() error = %v; want nil", err)
	}
	if result.Stdout != `{"id":"task-1"}` {
		t.Fatalf("Create() stdout = %q; want fake stdout", result.Stdout)
	}

	wantArgs := []string{
		"create",
		"--json",
		"Implement policy engine",
		"--description",
		"Add role checks",
		"--label",
		"kind:execution",
		"--label",
		"target:executor",
	}
	if !reflect.DeepEqual(runner.spec.Args, wantArgs) {
		t.Fatalf("args = %#v; want %#v", runner.spec.Args, wantArgs)
	}
	if runner.spec.Bin != "/opt/morph-agency/bin/bd" {
		t.Fatalf("bin = %q; want configured path", runner.spec.Bin)
	}
	if runner.spec.Dir != "/home/hermes/workspace" {
		t.Fatalf("dir = %q; want workspace", runner.spec.Dir)
	}
}

func TestReadCommandsRequestJSON(t *testing.T) {
	tests := []struct {
		name string
		run  func(Client) (Result, error)
		want []string
	}{
		{
			name: "show",
			run:  func(client Client) (Result, error) { return client.Show(context.Background(), "task-1") },
			want: []string{"show", "--json", "task-1"},
		},
		{
			name: "ready",
			run:  func(client Client) (Result, error) { return client.Ready(context.Background()) },
			want: []string{"ready", "--json"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			runner := &fakeRunner{}
			_, err := tt.run(Client{runCommand: runner})
			if err != nil {
				t.Fatalf("command error = %v; want nil", err)
			}
			if !reflect.DeepEqual(runner.spec.Args, tt.want) {
				t.Fatalf("args = %#v; want %#v", runner.spec.Args, tt.want)
			}
		})
	}
}

func TestUpdateAndCloseBuildTypedArgs(t *testing.T) {
	tests := []struct {
		name string
		run  func(Client) (Result, error)
		want []string
	}{
		{
			name: "update",
			run: func(client Client) (Result, error) {
				return client.Update(context.Background(), UpdateOptions{ID: "task-1", Message: "halfway", Status: "in_progress"})
			},
			want: []string{"update", "--json", "task-1", "--notes", "halfway", "--status", "in_progress"},
		},
		{
			name: "close",
			run:  func(client Client) (Result, error) { return client.Close(context.Background(), "task-1", "done") },
			want: []string{"close", "--json", "task-1", "--reason", "done"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			runner := &fakeRunner{}
			_, err := tt.run(Client{runCommand: runner})
			if err != nil {
				t.Fatalf("command error = %v; want nil", err)
			}
			if !reflect.DeepEqual(runner.spec.Args, tt.want) {
				t.Fatalf("args = %#v; want %#v", runner.spec.Args, tt.want)
			}
		})
	}
}

func TestCommandErrorIncludesContext(t *testing.T) {
	runner := &fakeRunner{result: Result{ExitCode: 7, Stderr: "bad things happened"}}
	client := Client{Profile: "executor", runCommand: runner}

	_, err := client.Show(context.Background(), "task-1")
	if !errors.Is(err, ErrCommandFailed) {
		t.Fatalf("Show() error = %v; want %v", err, ErrCommandFailed)
	}

	var commandErr *CommandError
	if !errors.As(err, &commandErr) {
		t.Fatalf("Show() error = %T; want *CommandError", err)
	}
	if commandErr.Profile != "executor" {
		t.Fatalf("profile = %q; want executor", commandErr.Profile)
	}
	if commandErr.ExitCode != 7 {
		t.Fatalf("exit code = %d; want 7", commandErr.ExitCode)
	}
}

func TestDefaultBinAndTimeout(t *testing.T) {
	runner := &fakeRunner{}
	client := Client{runCommand: runner}

	_, err := client.Ready(context.Background())
	if err != nil {
		t.Fatalf("Ready() error = %v; want nil", err)
	}
	if runner.spec.Bin != "bd" {
		t.Fatalf("bin = %q; want bd", runner.spec.Bin)
	}
	if runner.spec.Timeout != 30*time.Second {
		t.Fatalf("timeout = %s; want 30s", runner.spec.Timeout)
	}
}

type fakeRunner struct {
	spec   commandSpec
	result Result
	err    error
}

func (f *fakeRunner) Run(ctx context.Context, spec commandSpec) (Result, error) {
	f.spec = spec
	result := f.result
	result.Args = append([]string{spec.Bin}, spec.Args...)
	return result, f.err
}
