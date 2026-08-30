# @deepseek-ai/dsh-status

Agent-readable fleet status for DSH. The plugin reads the local USI monitor's
JSON endpoints and exposes two bounded, read-only tools:

- `server_status` returns DSH health, host resources, deployment drift, tunnel,
  workload, Nix, and repository synchronization state.
- `server_dsh_health` returns the focused DSH, resource, repository, and deploy
  subset for a quick incident check.

The plugin uses `baseUrl` and `requestTimeoutMs` configuration. It does not
start services, change deployments, read journals, or accept arbitrary commands.
The server monitor remains the authority for host-level access control.
