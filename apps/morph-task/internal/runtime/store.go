package runtime

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	_ "modernc.org/sqlite"
)

var (
	ErrAlreadyClaimed = errors.New("assignment already claimed")
	ErrNotAssigned    = errors.New("assignment not found")
	ErrTargetMismatch = errors.New("assignment target mismatch")
)

type Store struct {
	db *sql.DB
}

type Assignment struct {
	ProjectID     string
	BeadID        string
	TargetProfile string
	AssignedBy    string
	Status        string
	ClaimedBy     string
	ClaimedAt     string
	CreatedAt     string
	UpdatedAt     string
}

type CreateAssignmentRequest struct {
	ProjectID     string
	BeadID        string
	TargetProfile string
	AssignedBy    string
}

type ClaimRequest struct {
	ProjectID string
	BeadID    string
	Profile   string
}

type CompleteRequest struct {
	ProjectID string
	BeadID    string
	Profile   string
	Status    string
}

type AuditViolationRequest struct {
	ProjectID     string
	Profile       string
	Action        string
	TargetProfile string
	BeadID        string
	Reason        string
}

func Open(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open runtime db %s: %w", path, err)
	}
	db.SetMaxOpenConns(1)
	return &Store{db: db}, nil
}

func New(db *sql.DB) *Store {
	db.SetMaxOpenConns(1)
	return &Store{db: db}
}

func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

func (s *Store) Migrate(ctx context.Context) error {
	statements := []string{
		`PRAGMA foreign_keys = ON`,
		`CREATE TABLE IF NOT EXISTS runtime_assignments (
			project_id TEXT NOT NULL DEFAULT 'default',
			bead_id TEXT NOT NULL,
			target_profile TEXT NOT NULL,
			assigned_by TEXT NOT NULL DEFAULT 'orchestrator',
			status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'claimed', 'succeeded', 'failed', 'blocked', 'partial', 'cancelled')),
			claimed_by TEXT,
			claimed_at TEXT,
			created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
			updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
			PRIMARY KEY(project_id, bead_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_runtime_assignments_target_status ON runtime_assignments(project_id, target_profile, status, created_at)`,
		`CREATE TABLE IF NOT EXISTS runtime_locks (
			name TEXT PRIMARY KEY,
			owner_profile TEXT NOT NULL,
			expires_at TEXT NOT NULL,
			created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
		)`,
		`CREATE TABLE IF NOT EXISTS agent_messages (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			bead_id TEXT,
			from_profile TEXT NOT NULL,
			to_profile TEXT NOT NULL,
			intent TEXT NOT NULL,
			content TEXT NOT NULL,
			processed INTEGER NOT NULL DEFAULT 0,
			created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
		)`,
		`CREATE INDEX IF NOT EXISTS idx_agent_messages_target ON agent_messages(to_profile, processed, created_at)`,
		`CREATE TABLE IF NOT EXISTS profile_health (
			profile TEXT PRIMARY KEY,
			status TEXT NOT NULL DEFAULT 'unknown',
			consecutive_failures INTEGER NOT NULL DEFAULT 0,
			last_failure_at TEXT,
			updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
		)`,
		`CREATE TABLE IF NOT EXISTS policy_violations (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			project_id TEXT NOT NULL DEFAULT 'default',
			profile TEXT NOT NULL,
			action TEXT NOT NULL,
			target_profile TEXT,
			bead_id TEXT,
			reason TEXT NOT NULL,
			created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
		)`,
		`CREATE INDEX IF NOT EXISTS idx_policy_violations_profile ON policy_violations(project_id, profile, created_at)`,
	}
	for _, statement := range statements {
		if _, err := s.db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("migrate runtime db: %w", err)
		}
	}
	return nil
}

func (s *Store) AuditViolation(ctx context.Context, request AuditViolationRequest) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO policy_violations (project_id, profile, action, target_profile, bead_id, reason) VALUES (?, ?, ?, ?, ?, ?)`, defaultProject(request.ProjectID), request.Profile, request.Action, request.TargetProfile, request.BeadID, request.Reason)
	if err != nil {
		return fmt.Errorf("audit policy violation for profile %s action %s: %w", request.Profile, request.Action, err)
	}
	return nil
}

func (s *Store) Ping(ctx context.Context) error {
	if err := s.db.PingContext(ctx); err != nil {
		return fmt.Errorf("ping runtime db: %w", err)
	}
	return nil
}

func (s *Store) CreateAssignment(ctx context.Context, request CreateAssignmentRequest) error {
	assignedBy := request.AssignedBy
	if assignedBy == "" {
		assignedBy = "orchestrator"
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO runtime_assignments (project_id, bead_id, target_profile, assigned_by) VALUES (?, ?, ?, ?)`, defaultProject(request.ProjectID), request.BeadID, request.TargetProfile, assignedBy)
	if err != nil {
		return fmt.Errorf("create assignment %s: %w", request.BeadID, err)
	}
	return nil
}

func (s *Store) Claim(ctx context.Context, request ClaimRequest) (Assignment, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Assignment{}, fmt.Errorf("begin claim transaction: %w", err)
	}
	defer tx.Rollback()

	assignment, err := getAssignment(ctx, tx, defaultProject(request.ProjectID), request.BeadID)
	if err != nil {
		return Assignment{}, err
	}
	if assignment.TargetProfile != request.Profile {
		return Assignment{}, fmt.Errorf("%w: bead %s target=%s profile=%s", ErrTargetMismatch, request.BeadID, assignment.TargetProfile, request.Profile)
	}
	if assignment.Status != "pending" || assignment.ClaimedBy != "" {
		return Assignment{}, fmt.Errorf("%w: bead %s status=%s claimed_by=%s", ErrAlreadyClaimed, request.BeadID, assignment.Status, assignment.ClaimedBy)
	}

	now := time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
	result, err := tx.ExecContext(ctx, `UPDATE runtime_assignments
		SET status = 'claimed', claimed_by = ?, claimed_at = ?, updated_at = ?
		WHERE project_id = ? AND bead_id = ? AND target_profile = ? AND status = 'pending' AND claimed_by IS NULL`, request.Profile, now, now, defaultProject(request.ProjectID), request.BeadID, request.Profile)
	if err != nil {
		return Assignment{}, fmt.Errorf("claim assignment %s: %w", request.BeadID, err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return Assignment{}, fmt.Errorf("claim assignment %s rows affected: %w", request.BeadID, err)
	}
	if rows != 1 {
		return Assignment{}, fmt.Errorf("%w: bead %s", ErrAlreadyClaimed, request.BeadID)
	}

	assignment, err = getAssignment(ctx, tx, defaultProject(request.ProjectID), request.BeadID)
	if err != nil {
		return Assignment{}, err
	}
	if err := tx.Commit(); err != nil {
		return Assignment{}, fmt.Errorf("commit claim transaction: %w", err)
	}
	return assignment, nil
}

func (s *Store) Complete(ctx context.Context, request CompleteRequest) (Assignment, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Assignment{}, fmt.Errorf("begin complete transaction: %w", err)
	}
	defer tx.Rollback()

	assignment, err := getAssignment(ctx, tx, defaultProject(request.ProjectID), request.BeadID)
	if err != nil {
		return Assignment{}, err
	}
	if assignment.TargetProfile != request.Profile {
		return Assignment{}, fmt.Errorf("%w: bead %s target=%s profile=%s", ErrTargetMismatch, request.BeadID, assignment.TargetProfile, request.Profile)
	}
	if assignment.ClaimedBy != request.Profile {
		return Assignment{}, fmt.Errorf("%w: bead %s status=%s claimed_by=%s", ErrAlreadyClaimed, request.BeadID, assignment.Status, assignment.ClaimedBy)
	}

	now := time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
	result, err := tx.ExecContext(ctx, `UPDATE runtime_assignments
		SET status = ?, updated_at = ?
		WHERE project_id = ? AND bead_id = ? AND target_profile = ? AND claimed_by = ?`, request.Status, now, defaultProject(request.ProjectID), request.BeadID, request.Profile, request.Profile)
	if err != nil {
		return Assignment{}, fmt.Errorf("complete assignment %s: %w", request.BeadID, err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return Assignment{}, fmt.Errorf("complete assignment %s rows affected: %w", request.BeadID, err)
	}
	if rows != 1 {
		return Assignment{}, fmt.Errorf("%w: bead %s", ErrNotAssigned, request.BeadID)
	}

	assignment, err = getAssignment(ctx, tx, defaultProject(request.ProjectID), request.BeadID)
	if err != nil {
		return Assignment{}, err
	}
	if err := tx.Commit(); err != nil {
		return Assignment{}, fmt.Errorf("commit complete transaction: %w", err)
	}
	return assignment, nil
}

func (s *Store) GetAssignment(ctx context.Context, beadID string) (Assignment, error) {
	return getAssignment(ctx, s.db, "default", beadID)
}

type queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func getAssignment(ctx context.Context, queryer queryer, projectID string, beadID string) (Assignment, error) {
	var assignment Assignment
	err := queryer.QueryRowContext(ctx, `SELECT project_id, bead_id, target_profile, assigned_by, status,
		COALESCE(claimed_by, ''), COALESCE(claimed_at, ''), created_at, updated_at
		FROM runtime_assignments WHERE project_id = ? AND bead_id = ?`, defaultProject(projectID), beadID).Scan(
		&assignment.ProjectID,
		&assignment.BeadID,
		&assignment.TargetProfile,
		&assignment.AssignedBy,
		&assignment.Status,
		&assignment.ClaimedBy,
		&assignment.ClaimedAt,
		&assignment.CreatedAt,
		&assignment.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return Assignment{}, fmt.Errorf("%w: bead %s", ErrNotAssigned, beadID)
	}
	if err != nil {
		return Assignment{}, fmt.Errorf("get assignment %s: %w", beadID, err)
	}
	return assignment, nil
}

type PolicyViolation struct {
	ID            int64
	ProjectID     string
	Profile       string
	Action        string
	TargetProfile string
	BeadID        string
	Reason        string
	CreatedAt     string
}

type HealthSummary struct {
	ProjectID        string
	Assignments      map[string]int
	PolicyViolations int
	Profiles         map[string]string
}

func (s *Store) ListPolicyViolations(ctx context.Context, projectID string, limit int) ([]PolicyViolation, error) {
	if limit <= 0 || limit > 1000 {
		limit = 20
	}
	project := defaultProject(projectID)
	rows, err := s.db.QueryContext(ctx, `SELECT id, project_id, profile, action, COALESCE(target_profile, ''), COALESCE(bead_id, ''), reason, created_at
		FROM policy_violations WHERE project_id = ? ORDER BY id DESC LIMIT ?`, project, limit)
	if err != nil {
		return nil, fmt.Errorf("list policy violations for project %s: %w", project, err)
	}
	defer rows.Close()

	var violations []PolicyViolation
	for rows.Next() {
		var violation PolicyViolation
		if err := rows.Scan(&violation.ID, &violation.ProjectID, &violation.Profile, &violation.Action, &violation.TargetProfile, &violation.BeadID, &violation.Reason, &violation.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan policy violation: %w", err)
		}
		violations = append(violations, violation)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate policy violations: %w", err)
	}
	return violations, nil
}

func (s *Store) HealthSummary(ctx context.Context, projectID string) (HealthSummary, error) {
	summary := HealthSummary{ProjectID: defaultProject(projectID), Assignments: map[string]int{}, Profiles: map[string]string{}}
	project := summary.ProjectID

	rows, err := s.db.QueryContext(ctx, `SELECT status, count(*) FROM runtime_assignments WHERE project_id = ? GROUP BY status`, project)
	if err != nil {
		return summary, fmt.Errorf("query assignment health for project %s: %w", project, err)
	}
	for rows.Next() {
		var status string
		var count int
		if err := rows.Scan(&status, &count); err != nil {
			rows.Close()
			return summary, fmt.Errorf("scan assignment health: %w", err)
		}
		summary.Assignments[status] = count
	}
	if err := rows.Close(); err != nil {
		return summary, fmt.Errorf("close assignment health rows: %w", err)
	}

	if err := s.db.QueryRowContext(ctx, `SELECT count(*) FROM policy_violations WHERE project_id = ?`, project).Scan(&summary.PolicyViolations); err != nil {
		return summary, fmt.Errorf("query policy violation health for project %s: %w", project, err)
	}

	profileRows, err := s.db.QueryContext(ctx, `SELECT profile, status FROM profile_health ORDER BY profile`)
	if err != nil {
		return summary, fmt.Errorf("query profile health: %w", err)
	}
	defer profileRows.Close()
	for profileRows.Next() {
		var profile string
		var status string
		if err := profileRows.Scan(&profile, &status); err != nil {
			return summary, fmt.Errorf("scan profile health: %w", err)
		}
		summary.Profiles[profile] = status
	}
	if err := profileRows.Err(); err != nil {
		return summary, fmt.Errorf("iterate profile health: %w", err)
	}
	return summary, nil
}

func defaultProject(projectID string) string {
	if projectID == "" {
		return "default"
	}
	return projectID
}

func (s *Store) ListAssignments(ctx context.Context, projectID string) ([]Assignment, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT project_id, bead_id, target_profile, assigned_by, status,
		COALESCE(claimed_by, ''), COALESCE(claimed_at, ''), created_at, updated_at
		FROM runtime_assignments WHERE project_id = ? ORDER BY created_at`, defaultProject(projectID))
	if err != nil {
		return nil, fmt.Errorf("list assignments for project %s: %w", defaultProject(projectID), err)
	}
	defer rows.Close()

	var assignments []Assignment
	for rows.Next() {
		var assignment Assignment
		if err := rows.Scan(&assignment.ProjectID, &assignment.BeadID, &assignment.TargetProfile, &assignment.AssignedBy, &assignment.Status, &assignment.ClaimedBy, &assignment.ClaimedAt, &assignment.CreatedAt, &assignment.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan assignment: %w", err)
		}
		assignments = append(assignments, assignment)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate assignments: %w", err)
	}
	return assignments, nil
}
