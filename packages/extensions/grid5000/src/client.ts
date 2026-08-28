/** Grid'5000 REST client and normalized monitoring projections. */

import type { Config } from './index.ts'

/** Normalized Grid'5000 node record exposed to tools. */
export interface Grid5000Node {
  uid: string
  hostname?: string
  status?: string
  architecture?: string
  resources: Record<string, unknown>
  links?: Record<string, string>
}

/** Normalized Grid'5000 OAR job record exposed to tools. */
export interface Grid5000Job {
  id: number | string
  user?: string
  state?: string
  command?: string
  resources: unknown[]
  assigned_nodes: string[]
  raw: Record<string, unknown>
}

interface RawRecord { [key: string]: unknown }

function records(value: unknown): RawRecord[] {
  if (Array.isArray(value)) return value.filter((row): row is RawRecord => typeof row === 'object' && row !== null)
  if (typeof value === 'object' && value !== null) {
    const row = value as RawRecord
    for (const key of ['nodes', 'jobs', 'items', 'results']) if (key in row) return records(row[key])
    return [row]
  }
  return []
}

function asString(value: unknown): string | undefined { return typeof value === 'string' ? value : undefined }
function asList(value: unknown): unknown[] { return Array.isArray(value) ? value : [] }

function node(row: RawRecord): Grid5000Node {
  const hostname = asString(row.hostname)
  const status = asString(row.status)
  const architecture = asString(row.architecture)
  const links = typeof row.links === 'object' && row.links !== null ? row.links as Record<string, string> : undefined
  return {
    uid: asString(row.uid) ?? asString(row.id) ?? hostname ?? 'unknown',
    ...(hostname === undefined ? {} : { hostname }),
    ...(status === undefined ? {} : { status }),
    ...(architecture === undefined ? {} : { architecture }),
    resources: typeof row.resources === 'object' && row.resources !== null ? row.resources as Record<string, unknown> : row,
    ...(links === undefined ? {} : { links }),
  }
}

function job(row: RawRecord): Grid5000Job {
  const assigned = row.assigned_nodes ?? row.nodes ?? row.resources
  const assignedNodes = asList(assigned).flatMap((item) => {
    if (typeof item === 'string') return [item]
    if (typeof item === 'object' && item !== null) return [asString((item as RawRecord).uid) ?? asString((item as RawRecord).hostname)].filter((v): v is string => v !== undefined)
    return []
  })
  const user = asString(row.user)
  const state = asString(row.state)
  const command = asString(row.command)
  return {
    id: typeof row.id === 'number' || typeof row.id === 'string' ? row.id : 'unknown',
    ...(user === undefined ? {} : { user }),
    ...(state === undefined ? {} : { state }),
    ...(command === undefined ? {} : { command }),
    resources: asList(row.resources),
    assigned_nodes: assignedNodes,
    raw: row,
  }
}

function path(base: string, site: string, suffix: string): string {
  return `${base.replace(/\/$/, '')}/sites/${encodeURIComponent(site)}/${suffix}`
}

/** REST client used by the Grid'5000 tools. */
export interface Grid5000Client {
  nodes(site: string, filter?: string): Promise<Grid5000Node[]>
  jobs(site: string, state?: string, user?: string): Promise<Grid5000Job[]>
  capacity(site: string): Promise<JsonCapacity>
}

/** Aggregate node capacity returned by the capacity tool. */
export interface JsonCapacity {
  site: string
  nodes: number
  byStatus: Record<string, number>
  resources: { cpu: number; cores: number; threads: number; memoryBytes: number; gpus: number }
}

/** Create an authenticated, timeout-bounded Grid'5000 REST client.
 * @param config Validated endpoint, credential, timeout, and result limits.
 * @returns A client that reads normalized nodes, jobs, and capacity.
 */
export function createGrid5000Client(config: Config): Grid5000Client {
  const request = async (url: string): Promise<unknown> => {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), config.requestTimeoutMs)
    try {
      const response = await fetch(url, { signal: controller.signal, headers: config.apiToken ? { authorization: `Bearer ${config.apiToken}` } : {} })
      if (!response.ok) throw new Error(`Grid'5000 API ${response.status} ${response.statusText} for ${url}`)
      return await response.json() as unknown
    } finally { clearTimeout(timer) }
  }
  const listNodes = async (site: string): Promise<Grid5000Node[]> => records(await request(path(config.apiBaseUrl, site, 'nodes'))).map(node).slice(0, config.maxItems)
  const client: Grid5000Client = {
    nodes: async (site, filter) => {
      const rows = await listNodes(site)
      return filter === undefined ? rows : rows.filter(item => item.uid === filter || item.hostname === filter)
    },
    jobs: async (site, state, user) => {
      const query = new URLSearchParams()
      if (state !== undefined) query.set('state', state)
      if (user !== undefined) query.set('user', user)
      const suffix = `jobs${query.size > 0 ? `?${query}` : ''}`
      return records(await request(path(config.apiBaseUrl, site, suffix))).map(job).slice(0, config.maxItems)
    },
    capacity: async (site) => {
      const nodes = await listNodes(site)
      const byStatus: Record<string, number> = {}
      const resources = { cpu: 0, cores: 0, threads: 0, memoryBytes: 0, gpus: 0 }
      for (const item of nodes) {
        const status = item.status ?? 'unknown'; byStatus[status] = (byStatus[status] ?? 0) + 1
        const values = item.resources
        for (const [key, target] of [['cpu', 'cpu'], ['core', 'cores'], ['core_count', 'cores'], ['thread', 'threads'], ['thread_count', 'threads'], ['gpu', 'gpus'], ['gpu_count', 'gpus']] as const) {
          const value = Number(values[key]); if (Number.isFinite(value)) resources[target] += value
        }
        const memory = Number(values.memnode ?? values.memory ?? values.memory_bytes)
        if (Number.isFinite(memory)) resources.memoryBytes += memory
      }
      return { site, nodes: nodes.length, byStatus, resources }
    },
  }
  return client
}
