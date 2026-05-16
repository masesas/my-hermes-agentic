package cli

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/morph-ai-agent/ai-agent/internal/beads"
	"github.com/morph-ai-agent/ai-agent/internal/runtime"
)

func TestRunAssignCreatesAssignment(t *testing.T) {
	beadsClient := &fakeBeads{}
	store := &fakeStore{}

	stdout, stderr, code := runCLI(t, runOptions{
		args:  []string{"assign", "--target", "researcher", "--kind", "research", "task-2"},
		env:   map[string]string{"MORPH_PROFILE": "orchestrator"},
		beads: beadsClient,
		store: store,
	})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
	}
	if !strings.Contains(stdout, "assigned bead=task-2 target=researcher") {
		t.Fatalf("stdout = %q; want assigned message", stdout)
	}
	if store.created.BeadID != "task-2" || store.created.TargetProfile != "researcher" {
		t.Fatalf("assignment = %+v; want task-2/researcher", store.created)
	}
	if beadsClient.updateOptions.ID != "task-2" || beadsClient.updateOptions.Message != "assigned to researcher" {
		t.Fatalf("update options = %+v; want assignment update", beadsClient.updateOptions)
	}
}

func TestRunDoctorChecksBackends(t *testing.T) {
	beadsClient := &fakeBeads{readyResult: beads.Result{Stdout: `[]`}}
	store := &fakeStore{}

	stdout, stderr, code := runCLI(t, runOptions{
		args:  []string{"doctor"},
		env:   map[string]string{"MORPH_PROFILE": "orchestrator"},
		beads: beadsClient,
		store: store,
	})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
	}
	if !strings.Contains(stdout, "doctor ok profile=orchestrator beads=ok runtime=ok") {
		t.Fatalf("stdout = %q; want doctor ok", stdout)
	}
	if beadsClient.readyCalls != 1 {
		t.Fatalf("ready calls = %d; want 1", beadsClient.readyCalls)
	}
	if store.migrateCalls != 1 {
		t.Fatalf("migrate calls = %d; want 1", store.migrateCalls)
	}
}

func TestRunAuditsDeniedAction(t *testing.T) {
	store := &fakeStore{}

	_, stderr, code := runCLI(t, runOptions{
		args:  []string{"assign", "--target", "researcher", "task-1"},
		env:   map[string]string{"MORPH_PROFILE": "executor"},
		beads: &fakeBeads{},
		store: store,
	})

	if code != ExitDenied {
		t.Fatalf("Run() code = %d; want %d", code, ExitDenied)
	}
	if !strings.Contains(stderr, "denied: action denied") {
		t.Fatalf("stderr = %q; want denied", stderr)
	}
	if store.audit.Action != "assign" || store.audit.Profile != "executor" || store.audit.TargetProfile != "researcher" {
		t.Fatalf("audit = %+v; want executor assign researcher", store.audit)
	}
}

func TestRunCreatesBeadAndAssignment(t *testing.T) {
	beadsClient := &fakeBeads{createResult: beads.Result{Stdout: `{"id":"task-1"}`}}
	store := &fakeStore{}

	stdout, stderr, code := runCLI(t, runOptions{
		args: []string{"create", "--target", "executor", "--kind", "execution", "--title", "Implement policy engine", "--description", "Add checks"},
		env: map[string]string{
			"MORPH_PROFILE": "orchestrator",
		},
		beads: beadsClient,
		store: store,
	})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
	}
	if !strings.Contains(stdout, "created bead=task-1 target=executor kind=execution") {
		t.Fatalf("stdout = %q; want created message", stdout)
	}
	if stderr != "" {
		t.Fatalf("stderr = %q; want empty", stderr)
	}
	if beadsClient.createOptions.Title != "Implement policy engine" {
		t.Fatalf("create title = %q; want title", beadsClient.createOptions.Title)
	}
	if beadsClient.createOptions.Target != "executor" {
		t.Fatalf("create target = %q; want executor", beadsClient.createOptions.Target)
	}
	if store.created.ProjectID != "default" {
		t.Fatalf("assignment project = %q; want default", store.created.ProjectID)
	}
	if store.created.BeadID != "task-1" {
		t.Fatalf("assignment bead = %q; want task-1", store.created.BeadID)
	}
	if store.created.AssignedBy != "orchestrator" {
		t.Fatalf("assigned by = %q; want orchestrator", store.created.AssignedBy)
	}
}

func TestRunClaimsAssignmentAndUpdatesBead(t *testing.T) {
	beadsClient := &fakeBeads{}
	store := &fakeStore{claimAssignment: runtime.Assignment{BeadID: "task-1", TargetProfile: "executor", Status: "claimed", ClaimedBy: "executor"}}

	stdout, stderr, code := runCLI(t, runOptions{
		args: []string{"claim", "--target", "executor", "task-1"},
		env: map[string]string{
			"MORPH_PROFILE": "executor",
		},
		beads: beadsClient,
		store: store,
	})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
	}
	if !strings.Contains(stdout, "claimed bead=task-1 target=executor") {
		t.Fatalf("stdout = %q; want claimed message", stdout)
	}
	if store.claimed.BeadID != "task-1" {
		t.Fatalf("claimed bead = %q; want task-1", store.claimed.BeadID)
	}
	if beadsClient.updateOptions.ID != "task-1" {
		t.Fatalf("updated id = %q; want task-1", beadsClient.updateOptions.ID)
	}
	if beadsClient.updateOptions.Status != "in_progress" {
		t.Fatalf("updated status = %q; want in_progress", beadsClient.updateOptions.Status)
	}
}

func TestRunDeniesWorkerCreateBeforeBackend(t *testing.T) {
	beadsClient := &fakeBeads{}
	store := &fakeStore{}

	_, stderr, code := runCLI(t, runOptions{
		args: []string{"create", "--target", "executor", "--kind", "execution", "--title", "Nope"},
		env: map[string]string{
			"MORPH_PROFILE": "executor",
		},
		beads: beadsClient,
		store: store,
	})

	if code != ExitDenied {
		t.Fatalf("Run() code = %d; want %d", code, ExitDenied)
	}
	if !strings.Contains(stderr, "denied: action denied") {
		t.Fatalf("stderr = %q; want action denied", stderr)
	}
	if beadsClient.createCalls != 0 {
		t.Fatalf("create calls = %d; want 0", beadsClient.createCalls)
	}
	if store.audit.Action != "create" {
		t.Fatalf("audit action = %q; want create", store.audit.Action)
	}
}

func TestRunDeniesCrossProfileClaimBeforeBackend(t *testing.T) {
	beadsClient := &fakeBeads{}
	store := &fakeStore{}

	_, stderr, code := runCLI(t, runOptions{
		args: []string{"claim", "--target", "researcher", "task-1"},
		env: map[string]string{
			"MORPH_PROFILE": "executor",
		},
		beads: beadsClient,
		store: store,
	})

	if code != ExitDenied {
		t.Fatalf("Run() code = %d; want %d", code, ExitDenied)
	}
	if !strings.Contains(stderr, "denied: target denied") {
		t.Fatalf("stderr = %q; want target denied", stderr)
	}
	if store.claimCalls != 0 {
		t.Fatalf("claim calls = %d; want 0", store.claimCalls)
	}
}

func TestRunProgressUpdatesBead(t *testing.T) {
	beadsClient := &fakeBeads{}
	store := &fakeStore{}

	stdout, stderr, code := runCLI(t, runOptions{
		args:  []string{"progress", "--target", "executor", "--message", "halfway", "task-1"},
		env:   map[string]string{"MORPH_PROFILE": "executor"},
		beads: beadsClient,
		store: store,
	})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
	}
	if !strings.Contains(stdout, "progress bead=task-1") {
		t.Fatalf("stdout = %q; want progress message", stdout)
	}
	if beadsClient.updateOptions.ID != "task-1" || beadsClient.updateOptions.Message != "halfway" {
		t.Fatalf("update options = %+v; want progress update", beadsClient.updateOptions)
	}
	if store.claimCalls != 0 {
		t.Fatalf("claim calls = %d; want 0", store.claimCalls)
	}
}

func TestRunResultCompletesAssignmentAndUpdatesBead(t *testing.T) {
	beadsClient := &fakeBeads{}
	store := &fakeStore{completeAssignment: runtime.Assignment{BeadID: "task-1", TargetProfile: "executor", Status: "succeeded", ClaimedBy: "executor"}}

	stdout, stderr, code := runCLI(t, runOptions{
		args:  []string{"result", "--target", "executor", "--kind", "execution", "--status", "succeeded", "--message", "done", "task-1"},
		env:   map[string]string{"MORPH_PROFILE": "executor"},
		beads: beadsClient,
		store: store,
	})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
	}
	if !strings.Contains(stdout, "result bead=task-1 status=succeeded target=executor") {
		t.Fatalf("stdout = %q; want result message", stdout)
	}
	if store.completed.Status != "succeeded" {
		t.Fatalf("complete status = %q; want succeeded", store.completed.Status)
	}
	if beadsClient.updateOptions.Status != "succeeded" || beadsClient.updateOptions.Message != "done" {
		t.Fatalf("update options = %+v; want result update", beadsClient.updateOptions)
	}
}

func TestRunCloseCallsBeadsClose(t *testing.T) {
	beadsClient := &fakeBeads{}
	store := &fakeStore{}

	stdout, stderr, code := runCLI(t, runOptions{
		args:  []string{"close", "--reason", "accepted", "task-1"},
		env:   map[string]string{"MORPH_PROFILE": "orchestrator"},
		beads: beadsClient,
		store: store,
	})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
	}
	if !strings.Contains(stdout, "closed bead=task-1") {
		t.Fatalf("stdout = %q; want closed message", stdout)
	}
	if beadsClient.closeID != "task-1" || beadsClient.closeReason != "accepted" {
		t.Fatalf("close = %q/%q; want task-1/accepted", beadsClient.closeID, beadsClient.closeReason)
	}
}

func TestRunReadyAndShowProxyJSON(t *testing.T) {
	tests := []struct {
		name  string
		args  []string
		setup func(*fakeBeads)
		want  string
	}{
		{
			name:  "ready",
			args:  []string{"ready"},
			setup: func(client *fakeBeads) { client.readyResult = beads.Result{Stdout: `[{"id":"task-1"}]`} },
			want:  `[{"id":"task-1"}]`,
		},
		{
			name:  "show",
			args:  []string{"show", "task-1"},
			setup: func(client *fakeBeads) { client.showResult = beads.Result{Stdout: `{"id":"task-1"}`} },
			want:  `{"id":"task-1"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			beadsClient := &fakeBeads{}
			tt.setup(beadsClient)
			stdout, stderr, code := runCLI(t, runOptions{
				args:  tt.args,
				env:   map[string]string{"MORPH_PROFILE": "orchestrator"},
				beads: beadsClient,
				store: &fakeStore{},
			})
			if code != ExitOK {
				t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
			}
			if strings.TrimSpace(stdout) != tt.want {
				t.Fatalf("stdout = %q; want %q", strings.TrimSpace(stdout), tt.want)
			}
		})
	}
}

func TestRunAuditAndHealth(t *testing.T) {
	tests := []struct {
		name  string
		args  []string
		store *fakeStore
		want  string
	}{
		{
			name:  "audit",
			args:  []string{"audit", "--limit", "5"},
			store: &fakeStore{violations: []runtime.PolicyViolation{{ID: 1, Profile: "executor", Action: "assign", TargetProfile: "researcher", Reason: "action denied"}}},
			want:  "executor",
		},
		{
			name:  "health",
			args:  []string{"health"},
			store: &fakeStore{health: runtime.HealthSummary{Assignments: map[string]int{"pending": 2}, PolicyViolations: 1, Profiles: map[string]string{"executor": "ok"}}},
			want:  "pending",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			stdout, stderr, code := runCLI(t, runOptions{
				args:  tt.args,
				env:   map[string]string{"MORPH_PROFILE": "orchestrator"},
				beads: &fakeBeads{},
				store: tt.store,
			})
			if code != ExitOK {
				t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
			}
			if !strings.Contains(stdout, tt.want) {
				t.Fatalf("stdout = %q; want substring %q", stdout, tt.want)
			}
		})
	}
}

func TestRunUsesProjectFlag(t *testing.T) {
	policyPath := writePolicyFixture(t, `
version: 1
projects:
  client-a:
    workspace: /tmp/client-a
    allowed_profiles:
      - orchestrator
      - executor
profiles:
  orchestrator:
    role: task_router
    can_create: true
    allowed_task_kinds:
      - execution
  executor:
    role: execution_worker
    can_claim_targets:
      - executor
    can_write_result_targets:
      - executor
    allowed_task_kinds:
      - execution
`)
	beadsClient := &fakeBeads{createResult: beads.Result{Stdout: `{"id":"task-9"}`}}
	store := &fakeStore{}

	stdout, stderr, code := runCLI(t, runOptions{
		args:  []string{"--project", "client-a", "create", "--target", "executor", "--kind", "execution", "--title", "Project scoped"},
		env:   map[string]string{"MORPH_PROFILE": "orchestrator", "MORPH_ROLE_POLICY": policyPath},
		beads: beadsClient,
		store: store,
	})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
	}
	if !strings.Contains(stdout, "created bead=task-9") {
		t.Fatalf("stdout = %q; want created", stdout)
	}
	if store.created.ProjectID != "client-a" {
		t.Fatalf("assignment project = %q; want client-a", store.created.ProjectID)
	}
}

func TestRunReconcileReportsDrift(t *testing.T) {
	beadsClient := &fakeBeads{readyResult: beads.Result{Stdout: `[{"id":"task-ready"}]`}}
	store := &fakeStore{assignments: []runtime.Assignment{{ProjectID: "client-a", BeadID: "task-runtime", TargetProfile: "executor", Status: "pending"}}}

	stdout, stderr, code := runCLI(t, runOptions{
		args:  []string{"--project", "client-a", "reconcile"},
		env:   map[string]string{"MORPH_PROFILE": "orchestrator", "MORPH_ROLE_POLICY": writeProjectPolicyFixture(t)},
		beads: beadsClient,
		store: store,
	})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d; stderr=%s", code, ExitOK, stderr)
	}
	if !strings.Contains(stdout, "bead_missing_runtime_assignment") {
		t.Fatalf("stdout = %q; want missing runtime issue", stdout)
	}
	if !strings.Contains(stdout, "task-ready") {
		t.Fatalf("stdout = %q; want ready bead id", stdout)
	}
}

func TestRunRequiresProfile(t *testing.T) {
	_, stderr, code := runCLI(t, runOptions{args: []string{"ready"}, env: map[string]string{}})

	if code != ExitUsage {
		t.Fatalf("Run() code = %d; want %d", code, ExitUsage)
	}
	if !strings.Contains(stderr, "missing MORPH_PROFILE") {
		t.Fatalf("stderr = %q; want missing profile", stderr)
	}
}

func TestRunLoadsPolicyFromEnv(t *testing.T) {
	policyPath := writePolicyFixture(t, `
version: 1
profiles:
  orchestrator:
    role: task_router
    can_create: true
    can_assign: true
    can_read_all: true
    can_claim_targets: []
    can_write_result_targets: []
    can_close: true
    allowed_task_kinds:
      - research
`)

	_, stderr, code := runCLI(t, runOptions{
		args: []string{"create", "--target", "executor", "--kind", "execution", "--title", "Denied by policy"},
		env: map[string]string{
			"MORPH_PROFILE":     "orchestrator",
			"MORPH_ROLE_POLICY": policyPath,
		},
		beads: &fakeBeads{},
		store: &fakeStore{},
	})

	if code != ExitDenied {
		t.Fatalf("Run() code = %d; want %d", code, ExitDenied)
	}
	if !strings.Contains(stderr, "task kind denied") {
		t.Fatalf("stderr = %q; want kind denied", stderr)
	}
}

func TestRunVersionDoesNotRequireProfile(t *testing.T) {
	stdout, stderr, code := runCLI(t, runOptions{args: []string{"--version"}, env: map[string]string{}})

	if code != ExitOK {
		t.Fatalf("Run() code = %d; want %d", code, ExitOK)
	}
	if strings.TrimSpace(stdout) != Version {
		t.Fatalf("stdout = %q; want version", stdout)
	}
	if stderr != "" {
		t.Fatalf("stderr = %q; want empty", stderr)
	}
}

type runOptions struct {
	args  []string
	env   map[string]string
	beads beadsClient
	store runtimeStore
}

func runCLI(t *testing.T, options runOptions) (string, string, int) {
	t.Helper()

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	code := Run(Options{
		Args: options.args,
		Getenv: func(key string) string {
			return options.env[key]
		},
		Stdout: &stdout,
		Stderr: &stderr,
		Beads:  options.beads,
		Store:  options.store,
	})
	return stdout.String(), stderr.String(), code
}

func writePolicyFixture(t *testing.T, content string) string {
	t.Helper()

	path := filepath.Join(t.TempDir(), "role-policy.yaml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write policy fixture: %v", err)
	}
	return path
}

type fakeBeads struct {
	createCalls   int
	showCalls     int
	readyCalls    int
	updateCalls   int
	closeCalls    int
	createOptions beads.CreateOptions
	updateOptions beads.UpdateOptions
	showID        string
	closeID       string
	closeReason   string
	createResult  beads.Result
	showResult    beads.Result
	readyResult   beads.Result
	updateResult  beads.Result
	closeResult   beads.Result
	createErr     error
	showErr       error
	readyErr      error
	updateErr     error
	closeErr      error
}

func (f *fakeBeads) Create(ctx context.Context, options beads.CreateOptions) (beads.Result, error) {
	f.createCalls++
	f.createOptions = options
	return f.createResult, f.createErr
}

func (f *fakeBeads) Show(ctx context.Context, id string) (beads.Result, error) {
	f.showCalls++
	f.showID = id
	return f.showResult, f.showErr
}

func (f *fakeBeads) Ready(ctx context.Context) (beads.Result, error) {
	f.readyCalls++
	return f.readyResult, f.readyErr
}

func (f *fakeBeads) Update(ctx context.Context, options beads.UpdateOptions) (beads.Result, error) {
	f.updateCalls++
	f.updateOptions = options
	return f.updateResult, f.updateErr
}

func (f *fakeBeads) Close(ctx context.Context, id string, reason string) (beads.Result, error) {
	f.closeCalls++
	f.closeID = id
	f.closeReason = reason
	return f.closeResult, f.closeErr
}

type fakeStore struct {
	migrateCalls       int
	createCalls        int
	claimCalls         int
	created            runtime.CreateAssignmentRequest
	claimed            runtime.ClaimRequest
	completed          runtime.CompleteRequest
	claimAssignment    runtime.Assignment
	completeAssignment runtime.Assignment
	violations         []runtime.PolicyViolation
	health             runtime.HealthSummary
	assignments        []runtime.Assignment
	audit              runtime.AuditViolationRequest
	migrateErr         error
	createErr          error
	claimErr           error
	completeErr        error
}

func (f *fakeStore) Migrate(ctx context.Context) error {
	f.migrateCalls++
	return f.migrateErr
}

func (f *fakeStore) CreateAssignment(ctx context.Context, request runtime.CreateAssignmentRequest) error {
	f.createCalls++
	f.created = request
	return f.createErr
}

func (f *fakeStore) Claim(ctx context.Context, request runtime.ClaimRequest) (runtime.Assignment, error) {
	f.claimCalls++
	f.claimed = request
	return f.claimAssignment, f.claimErr
}

func (f *fakeStore) Complete(ctx context.Context, request runtime.CompleteRequest) (runtime.Assignment, error) {
	f.completed = request
	return f.completeAssignment, f.completeErr
}

func (f *fakeStore) AuditViolation(ctx context.Context, request runtime.AuditViolationRequest) error {
	f.audit = request
	return nil
}

func (f *fakeStore) ListPolicyViolations(ctx context.Context, limit int) ([]runtime.PolicyViolation, error) {
	return f.violations, nil
}

func (f *fakeStore) HealthSummary(ctx context.Context) (runtime.HealthSummary, error) {
	return f.health, nil
}

func (f *fakeStore) ListAssignments(ctx context.Context, projectID string) ([]runtime.Assignment, error) {
	return f.assignments, nil
}

func writeProjectPolicyFixture(t *testing.T) string {
	t.Helper()
	return writePolicyFixture(t, `
version: 1
projects:
  client-a:
    workspace: /tmp/client-a
    allowed_profiles:
      - orchestrator
profiles:
  orchestrator:
    role: task_router
    can_create: true
    can_assign: true
    can_close: true
    allowed_task_kinds:
      - execution
`)
}
