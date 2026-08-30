import type { Context } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import { NO_START_CAPABILITIES, resolveChildCwd, type ResolvedSubagentStartRequest, type SubagentCapabilities, type SubagentProvider } from '@deepseek-ai/dsh-subagent'
import { startInProcessRun } from '@deepseek-ai/dsh-subagent-in-process-driver'
export const name = 'subagent-ssh'
export const inject = ['subagents']
export interface Config {
  providerName: string
  defaultHost: string
  sshBaseUrl: string
}
export const Config: z<Config> = z.object({
  providerName: z.string().default('ssh'),
  defaultHost: z.string().default(''),
  sshBaseUrl: z.string().default('http://127.0.0.1:8097/ssh'),
})
class SshProvider implements SubagentProvider {
  readonly capabilities: SubagentCapabilities = NO_START_CAPABILITIES
  readonly inheritsParentContext = false
  constructor(readonly name: string, private readonly config: { sshBaseUrl: string; defaultHost: string }) {}
  async start(req: ResolvedSubagentStartRequest) {
    const parentCwd = req.parent.session.header.cwd
    if (!parentCwd) throw new Error('subagent-ssh: parent has no cwd')
    resolveChildCwd('subagent-ssh', undefined, parentCwd)
    if (this.config.defaultHost.length > 0) {
      try {
        const res = await fetch(this.config.sshBaseUrl, { signal: AbortSignal.timeout(2000) })
        if (res.ok) {
          const data = await res.json() as { hosts?: { name: string }[] }
          const found = data.hosts?.some(h => h.name === this.config.defaultHost)
          if (!found) throw new Error(`subagent-ssh: host ${this.config.defaultHost} not in dynamic registry`)
        }
      } catch (e) {
        if (e instanceof Error && e.message.includes('not in dynamic')) throw e
      }
    }
    return startInProcessRun(req, {})
  }
}
export function apply(ctx: Context, config: Config): void {
  const resolved = {
    providerName: config.providerName ?? 'ssh',
    sshBaseUrl: config.sshBaseUrl ?? 'http://127.0.0.1:8097/ssh',
    defaultHost: config.defaultHost ?? '',
  } as { sshBaseUrl: string; defaultHost: string } & { providerName: string }
  ctx.subagents.registerProvider(new SshProvider(
    resolved.providerName,
    { sshBaseUrl: resolved.sshBaseUrl, defaultHost: resolved.defaultHost },
  ))
}
