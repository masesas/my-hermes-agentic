package policy

import (
	"errors"
	"testing"
)

func TestAuthorizeRoleBoundaries(t *testing.T) {
	cfg := DefaultConfig()

	tests := []struct {
		name    string
		request Request
		wantErr error
	}{
		{
			name: "orchestrator can create research task",
			request: Request{
				Profile: "orchestrator",
				Action:  ActionCreate,
				Target:  "researcher",
				Kind:    "research",
			},
		},
		{
			name: "orchestrator can assign execution task",
			request: Request{
				Profile: "orchestrator",
				Action:  ActionAssign,
				Target:  "executor",
				Kind:    "execution",
			},
		},
		{
			name: "orchestrator cannot claim worker task",
			request: Request{
				Profile: "orchestrator",
				Action:  ActionClaim,
				Target:  "executor",
			},
			wantErr: ErrActionDenied,
		},
		{
			name: "researcher cannot create task",
			request: Request{
				Profile: "researcher",
				Action:  ActionCreate,
				Target:  "executor",
				Kind:    "execution",
			},
			wantErr: ErrActionDenied,
		},
		{
			name: "researcher can claim researcher task",
			request: Request{
				Profile: "researcher",
				Action:  ActionClaim,
				Target:  "researcher",
			},
		},
		{
			name: "researcher cannot claim executor task",
			request: Request{
				Profile: "researcher",
				Action:  ActionClaim,
				Target:  "executor",
			},
			wantErr: ErrTargetDenied,
		},
		{
			name: "executor cannot assign task",
			request: Request{
				Profile: "executor",
				Action:  ActionAssign,
				Target:  "researcher",
				Kind:    "research",
			},
			wantErr: ErrActionDenied,
		},
		{
			name: "executor can write executor result",
			request: Request{
				Profile: "executor",
				Action:  ActionResult,
				Target:  "executor",
			},
		},
		{
			name: "executor cannot write researcher result",
			request: Request{
				Profile: "executor",
				Action:  ActionResult,
				Target:  "researcher",
			},
			wantErr: ErrTargetDenied,
		},
		{
			name: "executor cannot create research task",
			request: Request{
				Profile: "executor",
				Action:  ActionCreate,
				Target:  "researcher",
				Kind:    "research",
			},
			wantErr: ErrActionDenied,
		},
		{
			name: "unknown profile denied",
			request: Request{
				Profile: "designer",
				Action:  ActionClaim,
				Target:  "designer",
			},
			wantErr: ErrUnknownProfile,
		},
		{
			name: "unknown action denied",
			request: Request{
				Profile: "executor",
				Action:  Action("deploy"),
				Target:  "executor",
			},
			wantErr: ErrUnknownAction,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := cfg.Authorize(tt.request)
			if tt.wantErr == nil {
				if err != nil {
					t.Fatalf("Authorize() error = %v; want nil", err)
				}
				return
			}
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("Authorize() error = %v; want %v", err, tt.wantErr)
			}
		})
	}
}

func TestAuthorizeTaskKindBoundaries(t *testing.T) {
	cfg := DefaultConfig()

	tests := []struct {
		name    string
		request Request
		wantErr error
	}{
		{
			name: "orchestrator cannot create unsupported task kind",
			request: Request{
				Profile: "orchestrator",
				Action:  ActionCreate,
				Target:  "executor",
				Kind:    "finance",
			},
			wantErr: ErrKindDenied,
		},
		{
			name: "executor execution kind is allowed for result context",
			request: Request{
				Profile: "executor",
				Action:  ActionResult,
				Target:  "executor",
				Kind:    "execution",
			},
		},
		{
			name: "executor research kind is denied",
			request: Request{
				Profile: "executor",
				Action:  ActionResult,
				Target:  "executor",
				Kind:    "research",
			},
			wantErr: ErrKindDenied,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := cfg.Authorize(tt.request)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("Authorize() error = %v; want %v", err, tt.wantErr)
			}
		})
	}
}
