// mcp-call invokes a single tool on a hosted agent-brain MCP endpoint.
// Uses Streamable HTTP transport. Used by plugin hooks; not part of the server build.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	mcpclient "github.com/mark3labs/mcp-go/client"
	"github.com/mark3labs/mcp-go/client/transport"
	"github.com/mark3labs/mcp-go/mcp"
)

func main() {
	if len(os.Args) < 2 {
		fatal("usage: mcp-call <tool-name> [json-args]")
	}
	tool := os.Args[1]
	var args map[string]any
	if len(os.Args) > 2 {
		if err := json.Unmarshal([]byte(os.Args[2]), &args); err != nil {
			fatal(err)
		}
	} else {
		args = map[string]any{}
	}
	url := os.Getenv("NIGHTHAWK_MCP_URL")
	if url == "" {
		fatal("NIGHTHAWK_MCP_URL required")
	}
	headers, err := buildHeaders()
	if err != nil {
		fatal(err)
	}
	mergeEnvArgs(args)

	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	c, err := mcpclient.NewStreamableHttpClient(url, transport.WithHTTPHeaders(headers))
	if err != nil {
		fatal(err)
	}
	defer c.Close()
	if err := c.Start(ctx); err != nil {
		fatal(err)
	}
	initReq := mcp.InitializeRequest{}
	initReq.Params.ProtocolVersion = mcp.LATEST_PROTOCOL_VERSION
	initReq.Params.ClientInfo = mcp.Implementation{Name: "agent-brain-mcp-call", Version: "0.1.0"}
	if _, err := c.Initialize(ctx, initReq); err != nil {
		fatal(err)
	}
	req := mcp.CallToolRequest{Params: mcp.CallToolParams{Name: tool, Arguments: args}}
	res, err := c.CallTool(ctx, req)
	if err != nil {
		fatal(err)
	}
	if res.IsError {
		fatal(fmt.Errorf("%s: %v", tool, res.Content))
	}
	for _, content := range res.Content {
		if t, ok := content.(mcp.TextContent); ok {
			fmt.Print(t.Text)
			return
		}
	}
}

func mergeEnvArgs(args map[string]any) {
	if agent := os.Getenv("NIGHTHAWK_AGENT_ID"); agent != "" {
		args["agent_id"] = agent
	}
	if session := os.Getenv("NIGHTHAWK_SESSION_ID"); session != "" {
		args["session_id"] = session
	}
}

func buildHeaders() (map[string]string, error) {
	agent := os.Getenv("NIGHTHAWK_AGENT_ID")
	if agent == "" {
		return nil, fmt.Errorf("NIGHTHAWK_AGENT_ID required")
	}
	h := map[string]string{"X-Agent-ID": agent}
	if s := os.Getenv("NIGHTHAWK_SESSION_ID"); s != "" {
		h["X-Session-ID"] = s
	}
	if j := strings.TrimSpace(os.Getenv("NIGHTHAWK_JWT")); j != "" {
		h["Authorization"] = "Bearer " + j
		return h, nil
	}
	if k := os.Getenv("NIGHTHAWK_API_KEY"); k != "" {
		h["X-API-Key"] = k
		return h, nil
	}
	return nil, fmt.Errorf("set NIGHTHAWK_JWT or NIGHTHAWK_API_KEY")
}

func fatal(err any) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
