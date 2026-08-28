/** Grid'5000 REST monitoring and model-facing tools. @module @deepseek-ai/dsh-grid5000 */

import type { Context } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { JsonValue, ToolDefinition } from '@deepseek-ai/dsh-tools'
import type { Grid5000Client, Grid5000Job, Grid5000Node } from './client.ts'
import { createGrid5000Client } from './client.ts'

export const name = 'grid5000'
export const inject = ['tools', 'systemPrompt']

/** Configures the Grid'5000 API endpoint and monitoring scope. */
export interface Config {
  /** Grid'5000 REST API base URL. */
  apiBaseUrl: string
  /** Site used when a tool call omits `site`. */
  defaultSite: string
  /** Optional API token; it is sent only to Grid'5000. */
  apiToken?: string
  /** Maximum number of records returned by one tool call. */
  maxItems: number
  /** HTTP request timeout in milliseconds. */
  requestTimeoutMs: number
}

export const Config: z<Config> = z.object({
  apiBaseUrl: z.string().default('https://api.grid5000.fr/stable'),
  defaultSite: z.string().default('luxembourg'),
  apiToken: z.string().default(''),
  maxItems: z.number().min(1).max(1000).default(200),
  requestTimeoutMs: z.number().min(100).max(120_000).default(15_000),
})

function site(value: string | undefined, fallback: string): string {
  const result = value ?? fallback
  if (!/^[a-z0-9-]+$/i.test(result)) throw new Error(`invalid Grid'5000 site: ${JSON.stringify(result)}`)
  return result
}

function renderJson(_args: unknown, value: unknown): [{ type: 'text'; text: string }] {
  return [{ type: 'text', text: JSON.stringify(value, null, 2) }]
}

function tool<T extends ToolDefinition>(definition: T): T { return definition }

/** Register Grid'5000 capacity and work-monitoring tools. */
export function apply(ctx: Context, config: Config): void {
  const client = createGrid5000Client(config)
  ctx.systemPrompt.section({ name: 'grid5000:monitoring', order: 118, text: 'Grid\'5000 monitoring is available. Use grid5000_capacity for aggregate capacity, grid5000_nodes for node inventory, and grid5000_jobs to identify OAR work, assigned nodes, owners, and commands. Treat API timestamps and job state as a live snapshot.' })

  ctx.tools.register(tool(defineTool({
    name: 'grid5000_capacity',
    description: 'Show Grid\'5000 node capacity and availability for a site, including CPU cores, threads, memory, GPUs, and node status counts.',
    parameters: { site: { type: 'string', description: 'Grid\'5000 site name; defaults to the configured site.' } },
    output: { schema: { type: 'json' }, render: renderJson },
    execute: async args => client.capacity(site(args.site, config.defaultSite)) as unknown as JsonValue,
    presentCall: () => ({ card: 'generic', title: 'Read Grid\'5000 capacity', kind: 'read' }),
  })))

  ctx.tools.register(tool(defineTool({
    name: 'grid5000_nodes',
    description: 'List Grid\'5000 nodes and their advertised hardware and status. Filter by site or node name.',
    parameters: { site: { type: 'string', description: 'Grid\'5000 site name.' }, node: { type: 'string', description: 'Optional node UID or hostname filter.' } },
    output: { schema: { type: 'json' }, render: renderJson },
    execute: async args => client.nodes(site(args.site, config.defaultSite), args.node) as unknown as JsonValue,
    presentCall: () => ({ card: 'generic', title: 'List Grid\'5000 nodes', kind: 'read' }),
  })))

  ctx.tools.register(tool(defineTool({
    name: 'grid5000_jobs',
    description: 'List live and recent OAR jobs on Grid\'5000, including job owner, state, command, resource requests, and assigned nodes so agent work can be correlated with instances.',
    parameters: { site: { type: 'string', description: 'Grid\'5000 site name.' }, state: { type: 'string', description: 'Optional OAR state filter.' }, user: { type: 'string', description: 'Optional job owner filter.' } },
    output: { schema: { type: 'json' }, render: renderJson },
    execute: async args => client.jobs(site(args.site, config.defaultSite), args.state, args.user) as unknown as JsonValue,
    presentCall: () => ({ card: 'generic', title: 'List Grid\'5000 work', kind: 'read' }),
  })))
}

export type { Grid5000Client, Grid5000Job, Grid5000Node }
