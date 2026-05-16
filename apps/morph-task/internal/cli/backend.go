package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/morph-ai-agent/ai-agent/internal/beads"
	"github.com/morph-ai-agent/ai-agent/internal/policy"
	"github.com/morph-ai-agent/ai-agent/internal/runtime"
)

type commandMetadata struct {
	BeadID      string
	Title       string
	Description string
	Status      string
	Message     string
	Limit       int
}

type commandRequest struct {
	policy.Request
	Metadata commandMetadata
}

type beadsClient interface {
	Create(context.Context, beads.CreateOptions) (beads.Result, error)
	Show(context.Context, string) (beads.Result, error)
	Ready(context.Context) (beads.Result, error)
	Update(context.Context, beads.UpdateOptions) (beads.Result, error)
	Close(context.Context, string, string) (beads.Result, error)
}

type runtimeStore interface {
	Migrate(context.Context) error
	CreateAssignment(context.Context, runtime.CreateAssignmentRequest) error
	Claim(context.Context, runtime.ClaimRequest) (runtime.Assignment, error)
	Complete(context.Context, runtime.CompleteRequest) (runtime.Assignment, error)
	AuditViolation(context.Context, runtime.AuditViolationRequest) error
	ListPolicyViolations(context.Context, int) ([]runtime.PolicyViolation, error)
	HealthSummary(context.Context) (runtime.HealthSummary, error)
	ListAssignments(context.Context, string) ([]runtime.Assignment, error)
}

type closeableStore interface {
	Close() error
}

func executeBackend(ctx context.Context, cfg policy.Config, request commandRequest, profile string, injectedBeads beadsClient, injectedStore runtimeStore, getenv Getenv) (string, error) {
	client := injectedBeads
	if client == nil {
		client = beads.Client{
			Bin:       firstNonEmpty(getenv("MORPH_BEADS_BIN"), cfg.Backend.BeadsBin),
			Workspace: resolveWorkspace(cfg, request.Project, getenv),
			Timeout:   30 * time.Second,
			Profile:   profile,
		}
	}

	store := injectedStore
	if store == nil {
		dbPath := firstNonEmpty(getenv("MORPH_RUNTIME_DB"), cfg.Backend.RuntimeDB)
		if dbPath == "" {
			return "", errors.New("missing runtime db path; set MORPH_RUNTIME_DB or backend.runtime_db")
		}
		opened, err := runtime.Open(dbPath)
		if err != nil {
			return "", err
		}
		defer opened.Close()
		store = opened
	}

	if err := store.Migrate(ctx); err != nil {
		return "", err
	}

	switch request.Action {
	case policy.ActionCreate:
		result, err := client.Create(ctx, beads.CreateOptions{
			Title:       request.Metadata.Title,
			Description: request.Metadata.Description,
			Kind:        request.Kind,
			Target:      request.Target,
		})
		if err != nil {
			return "", err
		}
		beadID, err := parseBeadID(result.Stdout)
		if err != nil {
			return "", err
		}
		if err := store.CreateAssignment(ctx, runtime.CreateAssignmentRequest{ProjectID: request.Project, BeadID: beadID, TargetProfile: request.Target, AssignedBy: profile}); err != nil {
			return "", err
		}
		return fmt.Sprintf("created bead=%s target=%s kind=%s", beadID, request.Target, request.Kind), nil
	case policy.ActionAssign:
		_, err := client.Update(ctx, beads.UpdateOptions{ID: request.Metadata.BeadID, Message: "assigned to " + request.Target})
		if err != nil {
			return "", err
		}
		if err := store.CreateAssignment(ctx, runtime.CreateAssignmentRequest{ProjectID: request.Project, BeadID: request.Metadata.BeadID, TargetProfile: request.Target, AssignedBy: profile}); err != nil {
			return "", err
		}
		return fmt.Sprintf("assigned bead=%s target=%s", request.Metadata.BeadID, request.Target), nil
	case policy.ActionClaim:
		assignment, err := store.Claim(ctx, runtime.ClaimRequest{ProjectID: request.Project, BeadID: request.Metadata.BeadID, Profile: profile})
		if err != nil {
			return "", err
		}
		_, err = client.Update(ctx, beads.UpdateOptions{ID: request.Metadata.BeadID, Message: "claimed by " + profile, Status: "in_progress"})
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("claimed bead=%s target=%s", assignment.BeadID, assignment.TargetProfile), nil
	case policy.ActionProgress:
		_, err := client.Update(ctx, beads.UpdateOptions{ID: request.Metadata.BeadID, Message: request.Metadata.Message})
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("progress bead=%s", request.Metadata.BeadID), nil
	case policy.ActionResult:
		assignment, err := store.Complete(ctx, runtime.CompleteRequest{ProjectID: request.Project, BeadID: request.Metadata.BeadID, Profile: profile, Status: request.Metadata.Status})
		if err != nil {
			return "", err
		}
		_, err = client.Update(ctx, beads.UpdateOptions{ID: request.Metadata.BeadID, Message: request.Metadata.Message, Status: request.Metadata.Status})
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("result bead=%s status=%s target=%s", assignment.BeadID, assignment.Status, assignment.TargetProfile), nil
	case policy.ActionClose:
		_, err := client.Close(ctx, request.Metadata.BeadID, request.Metadata.Message)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("closed bead=%s", request.Metadata.BeadID), nil
	case policy.ActionReady:
		result, err := client.Ready(ctx)
		if err != nil {
			return "", err
		}
		return result.Stdout, nil
	case policy.ActionShow:
		result, err := client.Show(ctx, request.Metadata.BeadID)
		if err != nil {
			return "", err
		}
		return result.Stdout, nil
	case policy.ActionDoctor:
		_, err := client.Ready(ctx)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("doctor ok profile=%s beads=ok runtime=ok", profile), nil
	case policy.ActionAudit:
		violations, err := store.ListPolicyViolations(ctx, request.Metadata.Limit)
		if err != nil {
			return "", err
		}
		data, err := json.MarshalIndent(violations, "", "  ")
		if err != nil {
			return "", fmt.Errorf("encode audit output: %w", err)
		}
		return string(data), nil
	case policy.ActionHealth:
		summary, err := store.HealthSummary(ctx)
		if err != nil {
			return "", err
		}
		data, err := json.MarshalIndent(summary, "", "  ")
		if err != nil {
			return "", fmt.Errorf("encode health output: %w", err)
		}
		return string(data), nil
	case policy.ActionReconcile:
		return runReconcile(ctx, request.Project, client, store)
	default:
		return "", fmt.Errorf("backend execution for %s is not implemented yet", request.Action)
	}
}

func parseBeadID(stdout string) (string, error) {
	var payload map[string]any
	if err := json.Unmarshal([]byte(stdout), &payload); err != nil {
		return "", fmt.Errorf("parse bd JSON output: %w", err)
	}
	for _, key := range []string{"id", "ID", "bead_id", "beadId"} {
		if value, ok := payload[key].(string); ok && strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value), nil
		}
	}
	return "", fmt.Errorf("parse bd JSON output: missing bead id")
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

var _ = closeableStore(nil)

func auditDenied(ctx context.Context, cfg policy.Config, request commandRequest, profile string, reason error, injectedStore runtimeStore, getenv Getenv) {
	store := injectedStore
	if store == nil {
		dbPath := firstNonEmpty(getenv("MORPH_RUNTIME_DB"), cfg.Backend.RuntimeDB)
		if dbPath == "" || dbPath == ":memory:" {
			return
		}
		opened, err := runtime.Open(dbPath)
		if err != nil {
			return
		}
		defer opened.Close()
		store = opened
	}
	if err := store.Migrate(ctx); err != nil {
		return
	}
	_ = store.AuditViolation(ctx, runtime.AuditViolationRequest{
		ProjectID:     request.Project,
		Profile:       profile,
		Action:        string(request.Action),
		TargetProfile: request.Target,
		BeadID:        request.Metadata.BeadID,
		Reason:        reason.Error(),
	})
}

func resolveWorkspace(cfg policy.Config, projectID string, getenv Getenv) string {
	if workspace := firstNonEmpty(getenv("MORPH_BEADS_WORKSPACE")); workspace != "" {
		return workspace
	}
	if project, ok := cfg.Projects[projectID]; ok && strings.TrimSpace(project.Workspace) != "" {
		return strings.TrimSpace(project.Workspace)
	}
	return firstNonEmpty(cfg.Backend.BeadsWorkspace, ".")
}
