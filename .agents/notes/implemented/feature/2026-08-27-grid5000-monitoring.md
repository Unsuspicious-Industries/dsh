# Grid'5000 monitoring plugin

`@deepseek-ai/dsh-grid5000` provides an opt-in REST-backed monitoring adapter for Grid'5000 deployments. It exposes normalized node inventory, aggregate hardware capacity, and OAR job records through model-facing tools. Job records retain scheduler owner, command, resource requests, and assigned nodes so sessions can correlate work with allocated instances without embedding SSH credentials or node-local assumptions.

The adapter uses a configured API root, site, bearer token, item limit, and request timeout. It is read-only: provisioning and cancellation remain outside this package. Node-local process and GPU telemetry requires a provider with deployment-specific SSH or monitoring authentication and is documented as deferred work.

Verification covers response normalization, resource aggregation, query filters, and HTTP failures with a mocked REST boundary.
