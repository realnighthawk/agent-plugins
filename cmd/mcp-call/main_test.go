package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBuildHeaders_JWT(t *testing.T) {
	t.Setenv("NIGHTHAWK_JWT", "tok")
	t.Setenv("NIGHTHAWK_API_KEY", "")
	t.Setenv("NIGHTHAWK_AGENT_ID", "cursor-alice")
	t.Setenv("NIGHTHAWK_SESSION_ID", "sess-1")

	h, err := buildHeaders()
	require.NoError(t, err)
	assert.Equal(t, "Bearer tok", h["Authorization"])
	assert.Equal(t, "cursor-alice", h["X-Agent-ID"])
	assert.Equal(t, "sess-1", h["X-Session-ID"])
}

func TestBuildHeaders_APIKey(t *testing.T) {
	t.Setenv("NIGHTHAWK_JWT", "")
	t.Setenv("NIGHTHAWK_API_KEY", "key-1")
	t.Setenv("NIGHTHAWK_AGENT_ID", "cursor-alice")
	t.Setenv("NIGHTHAWK_SESSION_ID", "")

	h, err := buildHeaders()
	require.NoError(t, err)
	assert.Equal(t, "key-1", h["X-API-Key"])
	assert.NotContains(t, h, "Authorization")
}

func TestBuildHeaders_MissingAuth(t *testing.T) {
	t.Setenv("NIGHTHAWK_JWT", "")
	t.Setenv("NIGHTHAWK_API_KEY", "")
	t.Setenv("NIGHTHAWK_AGENT_ID", "cursor-alice")
	_, err := buildHeaders()
	assert.Error(t, err)
}

func TestBuildHeaders_MissingAgent(t *testing.T) {
	t.Setenv("NIGHTHAWK_JWT", "tok")
	t.Setenv("NIGHTHAWK_AGENT_ID", "")
	_, err := buildHeaders()
	assert.Error(t, err)
}
