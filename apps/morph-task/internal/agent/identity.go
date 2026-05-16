package agent

import (
	"errors"
	"strings"
)

var ErrMissingProfile = errors.New("missing MORPH_PROFILE")

type Getenv func(string) string

func ResolveProfile(getenv Getenv, override string) (string, error) {
	profile := strings.TrimSpace(override)
	if profile == "" {
		profile = strings.TrimSpace(getenv("MORPH_PROFILE"))
	}
	if profile == "" {
		return "", ErrMissingProfile
	}
	return profile, nil
}
