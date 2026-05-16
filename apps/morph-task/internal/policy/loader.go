package policy

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type policyFile struct {
	Backend  backendFile            `yaml:"backend"`
	Projects map[string]projectFile `yaml:"projects"`
	Profiles map[string]profileFile `yaml:"profiles"`
}

type projectFile struct {
	Workspace       string   `yaml:"workspace"`
	HandoffDir      string   `yaml:"handoff_dir"`
	AllowedProfiles []string `yaml:"allowed_profiles"`
}

type backendFile struct {
	BeadsBin       string `yaml:"beads_bin"`
	BeadsWorkspace string `yaml:"beads_workspace"`
	RuntimeDB      string `yaml:"runtime_db"`
	HandoffDir     string `yaml:"handoff_dir"`
}

type profileFile struct {
	Role                  string   `yaml:"role"`
	CanCreate             bool     `yaml:"can_create"`
	CanAssign             bool     `yaml:"can_assign"`
	CanReadAll            bool     `yaml:"can_read_all"`
	CanClaimTargets       []string `yaml:"can_claim_targets"`
	CanWriteResultTargets []string `yaml:"can_write_result_targets"`
	CanClose              bool     `yaml:"can_close"`
	AllowedTaskKinds      []string `yaml:"allowed_task_kinds"`
}

func LoadFile(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read policy file %s: %w", path, err)
	}

	var file policyFile
	if err := yaml.Unmarshal(data, &file); err != nil {
		return Config{}, fmt.Errorf("parse policy file %s: %w", path, err)
	}

	if len(file.Profiles) == 0 {
		return Config{}, fmt.Errorf("parse policy file %s: no profiles configured", path)
	}

	config := Config{
		Backend: Backend{
			BeadsBin:       file.Backend.BeadsBin,
			BeadsWorkspace: file.Backend.BeadsWorkspace,
			RuntimeDB:      file.Backend.RuntimeDB,
			HandoffDir:     file.Backend.HandoffDir,
		},
		Projects: make(map[string]Project, len(file.Projects)),
		Profiles: make(map[string]Profile, len(file.Profiles)),
	}
	for name, project := range file.Projects {
		config.Projects[name] = Project{Workspace: project.Workspace, HandoffDir: project.HandoffDir, AllowedProfiles: project.AllowedProfiles}
	}
	if len(config.Projects) == 0 {
		config.Projects["default"] = Project{Workspace: config.Backend.BeadsWorkspace, HandoffDir: config.Backend.HandoffDir, AllowedProfiles: []string{"orchestrator", "researcher", "executor"}}
	}

	for name, profile := range file.Profiles {
		config.Profiles[name] = Profile{
			Role:                  profile.Role,
			CanCreate:             profile.CanCreate,
			CanAssign:             profile.CanAssign,
			CanReadAll:            profile.CanReadAll,
			CanClaimTargets:       profile.CanClaimTargets,
			CanWriteResultTargets: profile.CanWriteResultTargets,
			CanClose:              profile.CanClose,
			AllowedTaskKinds:      profile.AllowedTaskKinds,
		}
	}

	return config, nil
}
