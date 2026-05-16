package policy

import (
	"errors"
	"testing"
)

func TestRoleBoundaryRegressionMatrix(t *testing.T) {
	cfg := DefaultConfig()

	tests := []struct {
		name    string
		request Request
		wantErr error
	}{
		{
			name:    "researcher cannot assign through wrapper",
			request: Request{Profile: "researcher", Action: ActionAssign, Target: "executor", Kind: "execution"},
			wantErr: ErrActionDenied,
		},
		{
			name:    "researcher cannot close through wrapper",
			request: Request{Profile: "researcher", Action: ActionClose},
			wantErr: ErrActionDenied,
		},
		{
			name:    "researcher cannot execute result kind",
			request: Request{Profile: "researcher", Action: ActionResult, Target: "researcher", Kind: "execution"},
			wantErr: ErrKindDenied,
		},
		{
			name:    "executor cannot assign through wrapper",
			request: Request{Profile: "executor", Action: ActionAssign, Target: "researcher", Kind: "research"},
			wantErr: ErrActionDenied,
		},
		{
			name:    "executor cannot close through wrapper",
			request: Request{Profile: "executor", Action: ActionClose},
			wantErr: ErrActionDenied,
		},
		{
			name:    "executor cannot research result kind",
			request: Request{Profile: "executor", Action: ActionResult, Target: "executor", Kind: "research"},
			wantErr: ErrKindDenied,
		},
		{
			name:    "orchestrator cannot claim executor work",
			request: Request{Profile: "orchestrator", Action: ActionClaim, Target: "executor", Kind: "execution"},
			wantErr: ErrActionDenied,
		},
		{
			name:    "orchestrator cannot write executor result",
			request: Request{Profile: "orchestrator", Action: ActionResult, Target: "executor", Kind: "execution"},
			wantErr: ErrActionDenied,
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
