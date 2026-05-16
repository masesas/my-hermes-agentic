package policy

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestLoadFileAuthorizesFromYAML(t *testing.T) {
	path := writePolicyFile(t, `
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
      - execution
  researcher:
    role: research_worker
    can_create: false
    can_assign: false
    can_read_all: false
    can_claim_targets:
      - researcher
    can_write_result_targets:
      - researcher
    can_close: false
    allowed_task_kinds:
      - research
`)

	cfg, err := LoadFile(path)
	if err != nil {
		t.Fatalf("LoadFile() error = %v; want nil", err)
	}

	if err := cfg.Authorize(Request{Profile: "orchestrator", Action: ActionCreate, Target: "researcher", Kind: "research"}); err != nil {
		t.Fatalf("Authorize(orchestrator create) error = %v; want nil", err)
	}

	err = cfg.Authorize(Request{Profile: "researcher", Action: ActionAssign, Target: "orchestrator", Kind: "research"})
	if !errors.Is(err, ErrActionDenied) {
		t.Fatalf("Authorize(researcher assign) error = %v; want %v", err, ErrActionDenied)
	}
}

func TestLoadFileReadsBackendConfig(t *testing.T) {
	path := writePolicyFile(t, `
version: 1
backend:
  beads_bin: /opt/morph-agency/bin/bd
  beads_workspace: /home/hermes/workspace
  runtime_db: /var/lib/morph-agency/queue.db
  handoff_dir: /var/lib/morph-agency/handoff
profiles:
  orchestrator:
    role: task_router
    can_create: true
    allowed_task_kinds:
      - execution
`)

	cfg, err := LoadFile(path)
	if err != nil {
		t.Fatalf("LoadFile() error = %v; want nil", err)
	}
	if cfg.Backend.BeadsBin != "/opt/morph-agency/bin/bd" {
		t.Fatalf("beads bin = %q; want configured path", cfg.Backend.BeadsBin)
	}
	if cfg.Backend.RuntimeDB != "/var/lib/morph-agency/queue.db" {
		t.Fatalf("runtime db = %q; want configured path", cfg.Backend.RuntimeDB)
	}
}

func TestLoadFileRejectsEmptyProfiles(t *testing.T) {
	path := writePolicyFile(t, `version: 1
profiles: {}
`)

	_, err := LoadFile(path)
	if err == nil {
		t.Fatal("LoadFile() error = nil; want error")
	}
}

func writePolicyFile(t *testing.T, content string) string {
	t.Helper()

	path := filepath.Join(t.TempDir(), "role-policy.yaml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write policy fixture: %v", err)
	}
	return path
}
