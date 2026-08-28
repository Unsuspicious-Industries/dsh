/** Package-owned invariant companion for Grid'5000 monitoring. @module @deepseek-ai/dsh-grid5000/invariant */
import type { Context } from '@deepseek-ai/cordis'
import type { InvariantInstaller } from '@deepseek-ai/dsh-invariants'
const PACKAGE_NAME = '@deepseek-ai/dsh-grid5000'
/** Cordis companion plugin name. */
export const name = 'grid5000-invariant'
/** Service required by this companion. */
export const inject = ['invariants']
/** No runtime invariant: the adapter reads an external scheduler snapshot and owns no local lifecycle stream. */
const install: InvariantInstaller = () => {}
/**
 * Register this package's invariant companion.
 * @param ctx - Context carrying the invariant service.
 * @returns the disposer for the registration.
 */
export const apply = (ctx: Context): Promise<() => void> => Promise.resolve(ctx.invariants.register(PACKAGE_NAME, install))
