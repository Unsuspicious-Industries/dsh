# @deepseek-ai/dsh-ssh
Dynamic SSH host and tunnel registry for DSH. Reads the local USI monitor `/ssh` endpoint.

- `ssh_hosts` dynamic aliases, known-host, proxy jump
- `ssh_tunnels` active forwards, systemd units, pids
- `ssh_status` full snapshot

Fully dynamic: no static allowlist, observations only.
