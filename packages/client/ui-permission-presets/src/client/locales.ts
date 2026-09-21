/** `settings.permission` namespace dictionaries (the Permission row's copy). */

/**
 * Risk-gate copy names the product label of the unrestricted preset ("Root").
 * The label lives in one place — the host preset table's `name` — so these
 * strings stay deployment-neutral prose about what the mode allows.
 */

/** Simplified Chinese dictionary (the key-set source of truth). */
export const zh = {
  'title': '权限',
  'description': '选择新会话的默认权限模式',
  'loading': '加载中',
  'unavailable': '不可用',
  'confirm.title': '确认切换到 Root 权限？',
  'confirm.description': 'Root 权限会解除 workspace 限制，agent 可以直接读写主机上的任何文件，包括系统路径。仅在你信任后续任务时使用。',
  'confirm.acknowledge': '我已了解风险，并愿意继续',
  'confirm.cancel': '取消',
  'confirm.enable': '启用 Root',
} satisfies Record<string, string>

/** The settings.permission namespace key union. */
export type PermissionSettingsKey = keyof typeof zh

/** English dictionary, checked complete against the zh key set. */
export const en = {
  'title': 'Permission',
  'description': 'Choose the default permission mode for new sessions',
  'loading': 'Loading',
  'unavailable': 'Unavailable',
  'confirm.title': 'Switch to Root?',
  'confirm.description': 'Root removes the workspace confinement: the agent can read and write any file on the host, including system paths. Only use it when you trust subsequent tasks.',
  'confirm.acknowledge': 'I understand the risks and want to continue',
  'confirm.cancel': 'Cancel',
  'confirm.enable': 'Enable Root',
} satisfies Record<PermissionSettingsKey, string>

/** Simplified Chinese dictionary for the current-session popup gate. */
export const accessZh = {
  'confirm.title': '确认切换到 Root 权限？',
  'confirm.description': 'Root 权限会解除 workspace 限制，agent 可以直接读写主机上的任何文件，包括系统路径。仅在你信任当前任务时使用。',
  'confirm.acknowledge': '我已了解风险，并愿意继续',
  'confirm.cancel': '取消',
  'confirm.enable': '启用 Root',
} satisfies Record<string, string>

/** Current-session popup-gate key union. */
export type PermissionAccessKey = keyof typeof accessZh

/** English dictionary for the current-session popup gate. */
export const accessEn = {
  'confirm.title': 'Switch to Root?',
  'confirm.description': 'Root removes the workspace confinement: the agent can read and write any file on the host, including system paths. Only use it when you trust the current task.',
  'confirm.acknowledge': 'I understand the risks and want to continue',
  'confirm.cancel': 'Cancel',
  'confirm.enable': 'Enable Root',
} satisfies Record<PermissionAccessKey, string>
