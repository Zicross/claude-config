# n8n Workflow Management

Use this skill when working with n8n workflows — viewing, updating, debugging, or deploying changes. This covers both the MCP tools and the direct REST API.

## Available MCP Tools

The `n8n` MCP server provides these tools:

| Tool | Purpose |
|------|---------|
| `mcp__n8n__list-workflows` | List all workflows with IDs, names, active status |
| `mcp__n8n__get-workflow` | Get full JSON definition of a workflow by ID |
| `mcp__n8n__get-node-code` | Get code/parameters from a specific node (works on ALL node types — Code nodes return JS, Postgres nodes return query + options) |
| `mcp__n8n__update-node-code` | Update JavaScript in a **Code node only** (read-modify-write) |
| `mcp__n8n__execute-workflow` | Trigger a workflow execution |
| `mcp__n8n__get-execution` | Get execution results/status |

## MCP Tool Limitations

`update-node-code` **only works with Code nodes** (`n8n-nodes-base.code`). It cannot update:
- Postgres node queries
- HTTP Request node URLs/bodies
- If/Switch node conditions
- Form trigger fields
- Node positions, connections, or any structural changes

For anything beyond Code node JS updates, use the **REST API directly**.

## n8n REST API (Direct Access)

The n8n instance runs at `http://localhost:5678`. API key is in `.mcp.json` under `mcpServers.n8n.env.N8N_API_KEY`.

### Reading the API key

```bash
N8N_API_KEY=$(node -e "const c=JSON.parse(require('fs').readFileSync('.mcp.json','utf8'));console.log(c.mcpServers.n8n.env.N8N_API_KEY)")
```

### Key Endpoints

**List workflows:**
```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" http://localhost:5678/api/v1/workflows
```

**Get workflow:**
```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" http://localhost:5678/api/v1/workflows/{id}
```

**Update workflow (PUT):**
```bash
curl -s -X PUT -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
  --data-binary "@payload.json" \
  http://localhost:5678/api/v1/workflows/{id}
```

**Activate/deactivate:**
```bash
curl -s -X PATCH -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
  -d '{"active": true}' \
  http://localhost:5678/api/v1/workflows/{id}
```

**Execute workflow:**
```bash
curl -s -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
  -d '{"data": {"key": "value"}}' \
  http://localhost:5678/api/v1/workflows/{id}/run
```

**Get executions:**
```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" http://localhost:5678/api/v1/executions?workflowId={id}&limit=5
```

**Get single execution:**
```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" http://localhost:5678/api/v1/executions/{executionId}
```

### PUT Payload Format

The PUT endpoint is strict about allowed fields. Only include:

```json
{
  "name": "Workflow Name",
  "nodes": [...],
  "connections": {...},
  "settings": {
    "executionOrder": "v1"
  }
}
```

Do NOT include: `id`, `active`, `createdAt`, `updatedAt`, `versionId`, `shared`, `tags`, `staticData`, `meta`, `pinData`, `triggerCount`, `versionCounter`, `activeVersion`, `activeVersionId`, `isArchived`, `description`. The API returns `request/body/settings must NOT have additional properties` if extra fields are in `settings`.

### Windows/Git Bash Notes

- `curl -o` writes to Git Bash paths (`/tmp/...`) which Node.js resolves as `C:\tmp\...` (doesn't exist). Use `$TEMP` for temp files and reference as `process.env.TEMP` in Node.
- `/dev/stdin` doesn't work with Node.js on Windows. Write to temp files instead of piping.
- Use `--data-binary "@$TEMP/file.json"` for PUT payloads (not `-d @/tmp/...`).

## Workflow Update Patterns

### Pattern 1: Update a Code node (simple — use MCP)

```
1. mcp__n8n__get-node-code  → read current code
2. mcp__n8n__update-node-code → write new code
```

### Pattern 2: Update a Postgres node query (use API)

```
1. GET workflow JSON via API → save to temp file
2. Node.js script: parse JSON, find node by name, modify .parameters.query, write payload
3. PUT payload back via API
```

### Pattern 3: Add new nodes + rewire connections (use API)

```
1. GET workflow JSON
2. Node.js script:
   - Push new node objects into nodes array (with id, name, type, typeVersion, position, parameters, credentials)
   - Modify connections object to insert new nodes into the flow
   - Position new nodes logically (increment x by ~224 per node)
3. PUT payload back
```

### Pattern 4: Verify changes after deployment

```
1. mcp__n8n__get-node-code → confirm node has new code/query
2. mcp__n8n__get-workflow → confirm full structure
3. Optionally: mcp__n8n__execute-workflow → test run
4. mcp__n8n__get-execution → check results
```

## Credential Reference

All Postgres nodes use credential `id: cSvfjSCRPfp5qcYk`, name `QB_Postgres`. When adding new Postgres nodes, include:

```json
"credentials": {
  "postgres": {
    "id": "cSvfjSCRPfp5qcYk",
    "name": "QB_Postgres"
  }
}
```

## Important Reminders

- **JSON files on disk ≠ live n8n.** The `n8n-workflows/*.json` files are version-controlled exports. Editing them does NOT update live n8n. Always push changes via MCP or API.
- **Keep files and live n8n in sync.** After updating live n8n via API, also update the corresponding JSON file on disk so version control stays accurate.
- **Active workflows update immediately.** A PUT to an active workflow takes effect on the next execution. No restart needed.
- **Test with inactive workflows first** when making structural changes (new nodes, connection rewiring). Activate after verifying.
