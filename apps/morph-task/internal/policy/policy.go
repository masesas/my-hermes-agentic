package policy

import (
	"errors"
	"fmt"
)

type Action string

const (
	ActionCreate    Action = "create"
	ActionAssign    Action = "assign"
	ActionReady     Action = "ready"
	ActionShow      Action = "show"
	ActionClaim     Action = "claim"
	ActionProgress  Action = "progress"
	ActionResult    Action = "result"
	ActionClose     Action = "close"
	ActionDoctor    Action = "doctor"
	ActionAudit     Action = "audit"
	ActionHealth    Action = "health"
	ActionReconcile Action = "reconcile"
	ActionProjects  Action = "projects"
)

var (
	ErrUnknownProfile = errors.New("unknown profile")
	ErrUnknownAction  = errors.New("unknown action")
	ErrActionDenied   = errors.New("action denied")
	ErrTargetDenied   = errors.New("target denied")
	ErrKindDenied     = errors.New("task kind denied")
	ErrProjectDenied  = errors.New("project denied")
)

type Request struct {
	Profile string
	Action  Action
	Target  string
	Kind    string
	Project string
}

type Config struct {
	Backend  Backend
	Projects map[string]Project
	Profiles map[string]Profile
}

type Project struct {
	Workspace       string
	HandoffDir      string
	AllowedProfiles []string
}

type Backend struct {
	BeadsBin       string
	BeadsWorkspace string
	RuntimeDB      string
	HandoffDir     string
}

type Profile struct {
	Role                  string
	CanCreate             bool
	CanAssign             bool
	CanReadAll            bool
	CanClaimTargets       []string
	CanWriteResultTargets []string
	CanClose              bool
	AllowedTaskKinds      []string
}

func DefaultConfig() Config {
	return Config{
		Backend: Backend{
			BeadsBin:       "bd",
			BeadsWorkspace: ".",
			RuntimeDB:      ":memory:",
		},
		Projects: map[string]Project{
			"default": {Workspace: ".", AllowedProfiles: []string{"orchestrator", "researcher", "executor"}},
		},
		Profiles: map[string]Profile{
			"orchestrator": {
				Role:             "task_router",
				CanCreate:        true,
				CanAssign:        true,
				CanReadAll:       true,
				CanClose:         true,
				AllowedTaskKinds: []string{"research", "execution", "verification", "planning"},
			},
			"researcher": {
				Role:                  "research_worker",
				CanClaimTargets:       []string{"researcher"},
				CanWriteResultTargets: []string{"researcher"},
				AllowedTaskKinds:      []string{"research", "planning"},
			},
			"executor": {
				Role:                  "execution_worker",
				CanClaimTargets:       []string{"executor"},
				CanWriteResultTargets: []string{"executor"},
				AllowedTaskKinds:      []string{"execution", "verification"},
			},
		},
	}
}

func (c Config) Authorize(request Request) error {
	profile, ok := c.Profiles[request.Profile]
	if !ok {
		return fmt.Errorf("%w: %s", ErrUnknownProfile, request.Profile)
	}
	if request.Project != "" {
		project, ok := c.Projects[request.Project]
		if !ok {
			return fmt.Errorf("%w: %s", ErrProjectDenied, request.Project)
		}
		if len(project.AllowedProfiles) > 0 && !contains(project.AllowedProfiles, request.Profile) {
			return fmt.Errorf("%w: profile %s cannot access project %s", ErrProjectDenied, request.Profile, request.Project)
		}
	}

	switch request.Action {
	case ActionCreate:
		if !profile.CanCreate {
			return fmt.Errorf("%w: profile %s cannot create tasks", ErrActionDenied, request.Profile)
		}
		return authorizeKind(profile, request)
	case ActionAssign:
		if !profile.CanAssign {
			return fmt.Errorf("%w: profile %s cannot assign tasks", ErrActionDenied, request.Profile)
		}
		return authorizeKind(profile, request)
	case ActionReady, ActionShow, ActionDoctor, ActionAudit, ActionHealth, ActionReconcile, ActionProjects:
		return nil
	case ActionClaim:
		if len(profile.CanClaimTargets) == 0 {
			return fmt.Errorf("%w: profile %s cannot claim tasks", ErrActionDenied, request.Profile)
		}
		if !contains(profile.CanClaimTargets, request.Target) {
			return fmt.Errorf("%w: profile %s cannot claim target %s", ErrTargetDenied, request.Profile, request.Target)
		}
		return authorizeKind(profile, request)
	case ActionProgress, ActionResult:
		if len(profile.CanWriteResultTargets) == 0 {
			return fmt.Errorf("%w: profile %s cannot write task results", ErrActionDenied, request.Profile)
		}
		if !contains(profile.CanWriteResultTargets, request.Target) {
			return fmt.Errorf("%w: profile %s cannot write result for target %s", ErrTargetDenied, request.Profile, request.Target)
		}
		return authorizeKind(profile, request)
	case ActionClose:
		if !profile.CanClose {
			return fmt.Errorf("%w: profile %s cannot close tasks", ErrActionDenied, request.Profile)
		}
		return nil
	default:
		return fmt.Errorf("%w: %s", ErrUnknownAction, request.Action)
	}
}

func authorizeKind(profile Profile, request Request) error {
	if request.Kind != "" && !contains(profile.AllowedTaskKinds, request.Kind) {
		return fmt.Errorf("%w: profile %s cannot handle kind %s", ErrKindDenied, request.Profile, request.Kind)
	}
	return nil
}

func contains(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
