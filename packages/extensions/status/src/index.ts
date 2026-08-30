/** Compact read-only fleet status tools backed by the USI monitor API. @module @deepseek-ai/dsh-status */

import type { Context } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { JsonValue, ToolDefinition } from '@deepseek-ai/dsh-tools'

export const name = 'status'
export const inject = ['tools', 'systemPrompt']

/** Monitor endpoint and request budget for one status plugin instance. */
export interface Config {
  /** Base URL of the read-only USI monitor endpoint. */
  baseUrl: string
  /** Per-request HTTP timeout in milliseconds. */
  requestTimeoutMs: number
}

export const Config: z<Config> = z.object({
  baseUrl: z.string().default('http://127.0.0.1:8097'),
  requestTimeoutMs: z.number().min(100).max(30_000).default(5_000),
})

type SnapshotEndpoint = 'dsh' | 'metrics' | 'units' | 'repo' | 'deploy' | 'tunnel' | 'ssh' | 'workloads' | 'nix' | 'sync'

function tool<T extends ToolDefinition>(definition: T): T { return definition }

function renderJson(_args: unknown, value: unknown): [{ type: 'text'; text: string }] {
  return [{ type: 'text', text: JSON.stringify(value, null, 2) }]
}

function endpoint(baseUrl: string, path: SnapshotEndpoint): string {
  return `${baseUrl.replace(/\/$/, '')}/${path}`
}

/** Create the bounded monitor client used by both status tools. */
function client(config: Config) {
  const request = async (path: SnapshotEndpoint): Promise<unknown> => {
    const response = await fetch(endpoint(config.baseUrl, path), {
      signal: AbortSignal.timeout(config.requestTimeoutMs),
    })
    if (!response.ok) throw new Error(`status monitor ${response.status} ${response.statusText} for /${path}`)
    return response.json() as Promise<unknown>
  }

  return {
    snapshot: async () => {
      const paths: SnapshotEndpoint[] = ['dsh', 'metrics', 'units', 'repo', 'deploy', 'tunnel', 'ssh', 'workloads', 'nix', 'sync']
      const results = await Promise.all(paths.map(async (path) => {
        try { return [path, await request(path)] as const }
        catch (error) { return [path, { error: error instanceof Error ? error.message : String(error) }] as const }
      }))
      return Object.fromEntries(results)
    },
    health: async () => {
      const paths: SnapshotEndpoint[] = ['dsh', 'metrics']
      const results = await Promise.all(paths.map(async (path) => {
        try { return [path, await request(path)] as const }
        catch (error) { return [path, { error: error instanceof Error ? error.message : String(error) }] as const }
      }))
      return Object.fromEntries(results)
    },
  }
}

/** Register compact fleet health and DSH service status tools. */
export function apply(ctx: Context, config: Config): void {
  const monitor = client(config)
  ctx.systemPrompt.section({
    name: 'status:monitoring',
    order: 119,
    text: 'Agent-readable fleet status is available. Use server_status for a bounded read-only snapshot before diagnosing DSH, deployment, tunnel, model-door, or resource failures.',
  })

  ctx.tools.register(tool(defineTool({
    name: 'server_status',
    description: 'Read a bounded JSON snapshot of DSH health, host resources, deployment drift, tunnels, workloads, Nix state, and repository synchronization. Read-only.',
    parameters: {},
    output: { schema: { type: 'json' }, render: renderJson },
    execute: async () => monitor.snapshot() as unknown as JsonValue,
    presentCall: () => ({ card: 'generic', title: 'Read server status', kind: 'read' }),
  })))

  ctx.tools.register(tool(defineTool({
    name: 'server_dsh_health',
    description: 'Read the focused DSH health object and local model-door probe. Read-only.',
    parameters: {},
    output: { schema: { type: 'json' }, render: renderJson },
    execute: async () => monitor.health() as unknown as JsonValue,
    presentCall: () => ({ card: 'generic', title: 'Read DSH health', kind: 'read' }),
  })))
}
