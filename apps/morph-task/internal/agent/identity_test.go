package agent

import (
	"errors"
	"testing"
)

func TestResolveProfile(t *testing.T) {
	tests := []struct {
		name     string
		env      map[string]string
		override string
		want     string
		wantErr  error
	}{
		{
			name: "uses override first",
			env: map[string]string{
				"MORPH_PROFILE": "researcher",
			},
			override: "executor",
			want:     "executor",
		},
		{
			name: "uses MORPH_PROFILE",
			env: map[string]string{
				"MORPH_PROFILE": "researcher",
			},
			want: "researcher",
		},
		{
			name:    "missing profile",
			env:     map[string]string{},
			wantErr: ErrMissingProfile,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ResolveProfile(func(key string) string { return tt.env[key] }, tt.override)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("ResolveProfile() error = %v; want %v", err, tt.wantErr)
			}
			if got != tt.want {
				t.Fatalf("ResolveProfile() = %q; want %q", got, tt.want)
			}
		})
	}
}
