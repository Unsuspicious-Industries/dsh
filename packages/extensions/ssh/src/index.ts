import type { Context } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { JsonValue, ToolDefinition } from '@deepseek-ai/dsh-tools'
export const name = 'ssh'
export const inject = ['tools', 'systemPrompt']
export interface Config {
  monitorBaseUrl: string
  requestTimeoutMs: number
}
export const Config: z<Config> = z.object({
  monitorBaseUrl: z.string().default('http://127.0.0.1:8097'),
  requestTimeoutMs: z.number().min(100).max(30_000).default(5_000),
})
function tool<T extends ToolDefinition>(d: T): T { return d }
function renderJson(_a: unknown, v: unknown): [{ type: 'text'; text: string }] {
  return [{ type: 'text', text: JSON.stringify(v, null, 2) }]
}
function endpoint(base: string, path: string): string {
  return `${base.replace(/\/$/, '')}/${path}`
}
async function fetchJson(base: string, path: string, timeout: number): Promise<unknown> {
  const res = await fetch(endpoint(base, path), { signal: AbortSignal.timeout(timeout) })
  if (!res.ok) throw new Error(`ssh monitor ${res.status} ${res.statusText} for /${path}`)
  return res.json() as Promise<unknown>
}
export function apply(ctx: Context, config: Config): void {
  ctx.systemPrompt.section({ name: 'ssh:registry', order: 117, text: 'Dynamic SSH registry is available. Use ssh_hosts for declared aliases and known-host state, ssh_tunnels for active forwards. Host selection must use registry IDs only.' })
  ctx.tools.register(tool(defineTool({
    name: 'ssh_hosts',
    description: 'List dynamic SSH host aliases with hostname, user, port, jump host, and known-host presence.',
    parameters: {},
    output: { schema: { type: 'json' }, render: renderJson },
    execute: async () => {
      const data = await fetchJson(config.monitorBaseUrl, 'ssh', config.requestTimeoutMs) as { hosts: unknown }
      return (data.hosts ?? []) as unknown as JsonValue
    },
    presentCall: () => ({ card: 'generic', title: 'List SSH hosts', kind: 'read' }),
  })))
  ctx.tools.register(tool(defineTool({
    name: 'ssh_tunnels',
    description: 'List active SSH forwarding tunnels with direction, endpoints, owning unit, and process state.',
    parameters: {},
    output: { schema: { type: 'json' }, render: renderJson },
    execute: async () => {
      const data = await fetchJson(config.monitorBaseUrl, 'ssh', config.requestTimeoutMs) as { tunnels: unknown }
      return (data.tunnels ?? []) as unknown as JsonValue
    },
    presentCall: () => ({ card: 'generic', title: 'List SSH tunnels', kind: 'read' }),
  })))
  ctx.tools.register(tool(defineTool({
    name: 'ssh_status',
    description: 'Full dynamic SSH registry snapshot including hosts and tunnels.',
    parameters: {},
    output: { schema: { type: 'json' }, render: renderJson },
    execute: async () => await fetchJson(config.monitorBaseUrl, 'ssh', config.requestTimeoutMs) as unknown as JsonValue,
    presentCall: () => ({ card: 'generic', title: 'Read SSH registry', kind: 'read' }),
  })))
}
