/** Package-owned invariant companion for agent-readable status. @module @deepseek-ai/dsh-status/invariant */
import type { Context } from '@deepseek-ai/cordis'
import type { InvariantInstaller } from '@deepseek-ai/dsh-invariants'

const PACKAGE_NAME = '@deepseek-ai/dsh-status'

/** Cordis companion plugin name. */
export const name = 'status-invariant'
/** Service required by this companion. */
export const inject = ['invariants']
/** The adapter is read-only and owns no local lifecycle state. */
const install: InvariantInstaller = () => {}

/** Register this package's invariant companion. */
export const apply = (ctx: Context): Promise<() => void> =>
  Promise.resolve(ctx.invariants.register(PACKAGE_NAME, install))
