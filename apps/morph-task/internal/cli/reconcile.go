package cli

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/morph-ai-agent/ai-agent/internal/runtime"
)

type reconcileIssue struct {
	Type      string `json:"type"`
	ProjectID string `json:"project_id"`
	BeadID    string `json:"bead_id"`
	Detail    string `json:"detail"`
}

type reconcileReport struct {
	ProjectID          string           `json:"project_id"`
	RuntimeAssignments int              `json:"runtime_assignments"`
	ReadyBeads         int              `json:"ready_beads"`
	Issues             []reconcileIssue `json:"issues"`
}

func runReconcile(ctx context.Context, projectID string, client beadsClient, store runtimeStore) (string, error) {
	assignments, err := store.ListAssignments(ctx, projectID)
	if err != nil {
		return "", err
	}

	readyResult, err := client.Ready(ctx)
	if err != nil {
		return "", err
	}
	readyIDs, err := parseBeadIDs(readyResult.Stdout)
	if err != nil {
		return "", err
	}

	report := reconcileReport{ProjectID: projectID, RuntimeAssignments: len(assignments), ReadyBeads: len(readyIDs)}
	assignmentByID := make(map[string]runtime.Assignment, len(assignments))
	for _, assignment := range assignments {
		assignmentByID[assignment.BeadID] = assignment
		if _, err := client.Show(ctx, assignment.BeadID); err != nil {
			report.Issues = append(report.Issues, reconcileIssue{Type: "runtime_missing_bead", ProjectID: projectID, BeadID: assignment.BeadID, Detail: err.Error()})
		}
	}

	for _, beadID := range readyIDs {
		if _, ok := assignmentByID[beadID]; !ok {
			report.Issues = append(report.Issues, reconcileIssue{Type: "bead_missing_runtime_assignment", ProjectID: projectID, BeadID: beadID, Detail: "ready bead has no runtime assignment"})
		}
	}

	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return "", fmt.Errorf("encode reconcile output: %w", err)
	}
	return string(data), nil
}

func parseBeadIDs(stdout string) ([]string, error) {
	var payload any
	if err := json.Unmarshal([]byte(stdout), &payload); err != nil {
		return nil, fmt.Errorf("parse bd ready JSON output: %w", err)
	}
	return collectBeadIDs(payload), nil
}

func collectBeadIDs(value any) []string {
	var ids []string
	switch typed := value.(type) {
	case []any:
		for _, item := range typed {
			ids = append(ids, collectBeadIDs(item)...)
		}
	case map[string]any:
		for _, key := range []string{"id", "ID", "bead_id", "beadId"} {
			if id, ok := typed[key].(string); ok && id != "" {
				ids = append(ids, id)
				return ids
			}
		}
		for _, key := range []string{"items", "tasks", "issues", "ready"} {
			if nested, ok := typed[key]; ok {
				ids = append(ids, collectBeadIDs(nested)...)
			}
		}
	}
	return ids
}
