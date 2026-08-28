import { afterEach, describe, expect, it, vi } from 'vitest'
import { createGrid5000Client } from '../src/client.ts'

describe('Grid5000Client', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('normalizes nodes, jobs, and capacity while preserving job correlation fields', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) => ({
      ok: true,
      status: 200,
      statusText: 'OK',
      json: async () => url.endsWith('/nodes')
        ? [{ uid: 'n1', hostname: 'n1.luxembourg.grid5000.fr', status: 'Alive', resources: { core_count: 96, thread_count: 192, memnode: 524288, gpu_count: 4 } }]
        : [{ id: 329069, user: 'pkronlun', state: 'running', command: 'wirt --config config.toml', resources: [{ uid: 'n1' }] }],
    })))
    const client = createGrid5000Client({ apiBaseUrl: 'https://api.grid5000.fr/stable', defaultSite: 'luxembourg', maxItems: 10, requestTimeoutMs: 1000 })
    await expect(client.nodes('luxembourg')).resolves.toMatchObject([{ uid: 'n1', hostname: 'n1.luxembourg.grid5000.fr' }])
    await expect(client.jobs('luxembourg')).resolves.toMatchObject([{ id: 329069, user: 'pkronlun', assigned_nodes: ['n1'] }])
    await expect(client.capacity('luxembourg')).resolves.toEqual({ site: 'luxembourg', nodes: 1, byStatus: { Alive: 1 }, resources: { cpu: 0, cores: 96, threads: 192, memoryBytes: 524288, gpus: 4 } })
  })

  it('adds query filters and rejects unsuccessful API responses', async () => {
    const fetchMock = vi.fn(async (url: string) => {
      expect(url).toContain('state=running')
      expect(url).toContain('user=pkronlun')
      return { ok: false, status: 503, statusText: 'Unavailable', json: async () => ({}) }
    })
    vi.stubGlobal('fetch', fetchMock)
    const client = createGrid5000Client({ apiBaseUrl: 'https://api.grid5000.fr/stable', defaultSite: 'luxembourg', maxItems: 10, requestTimeoutMs: 1000 })
    await expect(client.jobs('luxembourg', 'running', 'pkronlun')).rejects.toThrow("Grid'5000 API 503")
  })
})
