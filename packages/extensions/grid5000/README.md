# @deepseek-ai/dsh-grid5000

Grid'5000 monitoring for DSH sessions. The plugin reads the Grid'5000 REST API and adds model-facing tools for node inventory, aggregate capacity, and OAR jobs. Job records retain owner, state, command, requested resources, and assigned nodes so work running on allocated instances can be correlated with capacity.

## Configuration

| key | default | meaning |
|---|---|---|
| `apiBaseUrl` | `https://api.grid5000.fr/stable` | Grid'5000 API root |
| `defaultSite` | `luxembourg` | site used when a call omits `site` |
| `apiToken` | unset | optional bearer token sent to the API |
| `maxItems` | `200` | maximum records returned by a call |
| `requestTimeoutMs` | `15000` | HTTP timeout |

## Tools

- `grid5000_capacity` summarizes node count, status counts, CPU, cores, threads, memory, and GPUs.
- `grid5000_nodes` lists normalized node records and supports UID/hostname filtering.
- `grid5000_jobs` lists OAR jobs and supports state and user filters.

The plugin is opt-in: add `@deepseek-ai/dsh-grid5000` to a profile or patch. It does not submit, cancel, or mutate jobs. Authentication for private Grid'5000 deployments belongs in the configured API or an API gateway; credentials are never included in model-visible output.

## Model Experience

### System prompt

#### What the model sees

The plugin adds one short instruction directing the model to use capacity, node, and job tools and to treat results as live snapshots.

##### Monitoring instruction

```markdown
Grid'5000 monitoring is available. Use grid5000_capacity for aggregate capacity, grid5000_nodes for node inventory, and grid5000_jobs to identify OAR work, assigned nodes, owners, and commands. Treat API timestamps and job state as a live snapshot.
```

#### Token effect

The instruction adds a small fixed amount of prompt text; tool results consume tokens only when called.

#### KV Cache effect

The fixed instruction can remain in the reusable prompt prefix; monitoring results vary per call and are not cached by this plugin.

## Known Limitations and Deferred Work

- The API adapter does not run SSH probes on compute nodes. A future provider can add authenticated process and GPU telemetry without changing the model-facing tool names.
- API response fields are normalized conservatively because Grid'5000 sites expose different resource naming conventions.
