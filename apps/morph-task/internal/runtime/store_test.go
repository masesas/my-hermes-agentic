package runtime

import (
	"context"
	"database/sql"
	"errors"
	"sync"
	"testing"

	_ "modernc.org/sqlite"
)

func TestMigrateCreatesRuntimeTables(t *testing.T) {
	store := newTestStore(t)

	for _, table := range []string{"runtime_assignments", "runtime_locks", "agent_messages", "profile_health", "policy_violations"} {
		t.Run(table, func(t *testing.T) {
			var name string
			err := store.db.QueryRowContext(context.Background(), `SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?`, table).Scan(&name)
			if err != nil {
				t.Fatalf("table %s missing: %v", table, err)
			}
			if name != table {
				t.Fatalf("table name = %q; want %q", name, table)
			}
		})
	}
}

func TestCreateAndClaimAssignment(t *testing.T) {
	store := newTestStore(t)
	ctx := context.Background()

	err := store.CreateAssignment(ctx, CreateAssignmentRequest{BeadID: "task-1", TargetProfile: "executor", AssignedBy: "orchestrator"})
	if err != nil {
		t.Fatalf("CreateAssignment() error = %v; want nil", err)
	}

	assignment, err := store.Claim(ctx, ClaimRequest{BeadID: "task-1", Profile: "executor"})
	if err != nil {
		t.Fatalf("Claim() error = %v; want nil", err)
	}
	if assignment.Status != "claimed" {
		t.Fatalf("status = %q; want claimed", assignment.Status)
	}
	if assignment.ClaimedBy != "executor" {
		t.Fatalf("claimed_by = %q; want executor", assignment.ClaimedBy)
	}
	if assignment.TargetProfile != "executor" {
		t.Fatalf("target = %q; want executor", assignment.TargetProfile)
	}
	if assignment.ClaimedAt == "" {
		t.Fatal("claimed_at is empty; want timestamp")
	}
}

func TestClaimRejectsWrongProfile(t *testing.T) {
	store := newTestStore(t)
	ctx := context.Background()

	err := store.CreateAssignment(ctx, CreateAssignmentRequest{BeadID: "task-1", TargetProfile: "researcher"})
	if err != nil {
		t.Fatalf("CreateAssignment() error = %v; want nil", err)
	}

	_, err = store.Claim(ctx, ClaimRequest{BeadID: "task-1", Profile: "executor"})
	if !errors.Is(err, ErrTargetMismatch) {
		t.Fatalf("Claim() error = %v; want %v", err, ErrTargetMismatch)
	}
}

func TestClaimRejectsMissingAssignment(t *testing.T) {
	store := newTestStore(t)

	_, err := store.Claim(context.Background(), ClaimRequest{BeadID: "missing", Profile: "executor"})
	if !errors.Is(err, ErrNotAssigned) {
		t.Fatalf("Claim() error = %v; want %v", err, ErrNotAssigned)
	}
}

func TestClaimIsAtomic(t *testing.T) {
	store := newTestStore(t)
	ctx := context.Background()

	err := store.CreateAssignment(ctx, CreateAssignmentRequest{BeadID: "task-1", TargetProfile: "executor"})
	if err != nil {
		t.Fatalf("CreateAssignment() error = %v; want nil", err)
	}

	const workers = 8
	var wg sync.WaitGroup
	results := make(chan error, workers)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := store.Claim(context.Background(), ClaimRequest{BeadID: "task-1", Profile: "executor"})
			results <- err
		}()
	}
	wg.Wait()
	close(results)

	successes := 0
	alreadyClaimed := 0
	for err := range results {
		if err == nil {
			successes++
			continue
		}
		if errors.Is(err, ErrAlreadyClaimed) {
			alreadyClaimed++
			continue
		}
		t.Fatalf("unexpected claim error: %v", err)
	}

	if successes != 1 {
		t.Fatalf("successful claims = %d; want 1", successes)
	}
	if alreadyClaimed != workers-1 {
		t.Fatalf("already claimed errors = %d; want %d", alreadyClaimed, workers-1)
	}
}

func newTestStore(t *testing.T) *Store {
	t.Helper()

	db, err := sql.Open("sqlite", "file::memory:?cache=shared")
	if err != nil {
		t.Fatalf("open sqlite memory db: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	store := New(db)
	if err := store.Migrate(context.Background()); err != nil {
		t.Fatalf("Migrate() error = %v; want nil", err)
	}
	return store
}

func TestCompleteAssignment(t *testing.T) {
	store := newTestStore(t)
	ctx := context.Background()

	if err := store.CreateAssignment(ctx, CreateAssignmentRequest{BeadID: "task-1", TargetProfile: "executor"}); err != nil {
		t.Fatalf("CreateAssignment() error = %v; want nil", err)
	}
	if _, err := store.Claim(ctx, ClaimRequest{BeadID: "task-1", Profile: "executor"}); err != nil {
		t.Fatalf("Claim() error = %v; want nil", err)
	}

	assignment, err := store.Complete(ctx, CompleteRequest{BeadID: "task-1", Profile: "executor", Status: "succeeded"})
	if err != nil {
		t.Fatalf("Complete() error = %v; want nil", err)
	}
	if assignment.Status != "succeeded" {
		t.Fatalf("status = %q; want succeeded", assignment.Status)
	}
}

func TestAuditViolation(t *testing.T) {
	store := newTestStore(t)
	ctx := context.Background()

	err := store.AuditViolation(ctx, AuditViolationRequest{Profile: "executor", Action: "assign", TargetProfile: "researcher", BeadID: "task-1", Reason: "action denied"})
	if err != nil {
		t.Fatalf("AuditViolation() error = %v; want nil", err)
	}

	var count int
	err = store.db.QueryRowContext(ctx, `SELECT count(*) FROM policy_violations WHERE profile = 'executor' AND action = 'assign' AND target_profile = 'researcher'`).Scan(&count)
	if err != nil {
		t.Fatalf("query policy violations: %v", err)
	}
	if count != 1 {
		t.Fatalf("policy violation count = %d; want 1", count)
	}
}

func TestListPolicyViolationsAndHealthSummary(t *testing.T) {
	store := newTestStore(t)
	ctx := context.Background()

	if err := store.CreateAssignment(ctx, CreateAssignmentRequest{BeadID: "task-1", TargetProfile: "executor"}); err != nil {
		t.Fatalf("CreateAssignment() error = %v; want nil", err)
	}
	if err := store.AuditViolation(ctx, AuditViolationRequest{Profile: "executor", Action: "assign", TargetProfile: "researcher", Reason: "denied"}); err != nil {
		t.Fatalf("AuditViolation() error = %v; want nil", err)
	}

	violations, err := store.ListPolicyViolations(ctx, "default", 10)
	if err != nil {
		t.Fatalf("ListPolicyViolations() error = %v; want nil", err)
	}
	if len(violations) != 1 || violations[0].Profile != "executor" {
		t.Fatalf("violations = %+v; want one executor violation", violations)
	}

	summary, err := store.HealthSummary(ctx, "default")
	if err != nil {
		t.Fatalf("HealthSummary() error = %v; want nil", err)
	}
	if summary.Assignments["pending"] != 1 {
		t.Fatalf("pending assignments = %d; want 1", summary.Assignments["pending"])
	}
	if summary.PolicyViolations != 1 {
		t.Fatalf("policy violations = %d; want 1", summary.PolicyViolations)
	}
}

func TestProjectIsolationForHealthAndAudit(t *testing.T) {
	ctx := context.Background()
	store := newTestStore(t)
	if err := store.Migrate(ctx); err != nil {
		t.Fatalf("Migrate() error = %v; want nil", err)
	}

	if err := store.CreateAssignment(ctx, CreateAssignmentRequest{ProjectID: "alpha", BeadID: "alpha-1", TargetProfile: "executor"}); err != nil {
		t.Fatalf("CreateAssignment(alpha) error = %v; want nil", err)
	}
	if err := store.CreateAssignment(ctx, CreateAssignmentRequest{ProjectID: "beta", BeadID: "beta-1", TargetProfile: "researcher"}); err != nil {
		t.Fatalf("CreateAssignment(beta) error = %v; want nil", err)
	}
	if err := store.AuditViolation(ctx, AuditViolationRequest{ProjectID: "alpha", Profile: "executor", Action: "assign", Reason: "denied"}); err != nil {
		t.Fatalf("AuditViolation(alpha) error = %v; want nil", err)
	}
	if err := store.AuditViolation(ctx, AuditViolationRequest{ProjectID: "beta", Profile: "executor", Action: "assign", Reason: "denied"}); err != nil {
		t.Fatalf("AuditViolation(beta) error = %v; want nil", err)
	}

	alphaSummary, err := store.HealthSummary(ctx, "alpha")
	if err != nil {
		t.Fatalf("HealthSummary(alpha) error = %v", err)
	}
	if alphaSummary.ProjectID != "alpha" {
		t.Fatalf("alpha project id = %q; want alpha", alphaSummary.ProjectID)
	}
	if alphaSummary.Assignments["pending"] != 1 || alphaSummary.PolicyViolations != 1 {
		t.Fatalf("alpha summary = %+v; want one pending one violation", alphaSummary)
	}

	betaSummary, err := store.HealthSummary(ctx, "beta")
	if err != nil {
		t.Fatalf("HealthSummary(beta) error = %v", err)
	}
	if betaSummary.Assignments["pending"] != 1 || betaSummary.PolicyViolations != 1 {
		t.Fatalf("beta summary = %+v; want isolated counts", betaSummary)
	}

	alphaViolations, err := store.ListPolicyViolations(ctx, "alpha", 10)
	if err != nil {
		t.Fatalf("ListPolicyViolations(alpha) error = %v", err)
	}
	if len(alphaViolations) != 1 || alphaViolations[0].ProjectID != "alpha" {
		t.Fatalf("alpha violations = %+v; want single alpha-scoped violation", alphaViolations)
	}

	betaViolations, err := store.ListPolicyViolations(ctx, "beta", 10)
	if err != nil {
		t.Fatalf("ListPolicyViolations(beta) error = %v", err)
	}
	if len(betaViolations) != 1 || betaViolations[0].ProjectID != "beta" {
		t.Fatalf("beta violations = %+v; want single beta-scoped violation", betaViolations)
	}
}
