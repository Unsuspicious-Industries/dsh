import type { HeroBrandMarkOwnerProps } from '@deepseek-ai/dsh-client-ui-conversation/client'
import type { SidebarBrandMarkOwnerProps } from '@deepseek-ai/dsh-client-ui-sidebar/client'

type OfficialBrandMarkProps = HeroBrandMarkOwnerProps & SidebarBrandMarkOwnerProps

/**
 * Render the USI monogram with the presentation requested by its host surface.
 * @param props - Host-supplied mark presentation.
 * @returns the USI brand mark.
 */
export function OfficialBrandMark({ size, className }: OfficialBrandMarkProps) {
  return (
    <svg
      aria-label="USI"
      className={className}
      fill="none"
      height={size}
      role="img"
      viewBox="0 0 64 64"
      width={size}
    >
      <rect fill="currentColor" height="64" rx="12" width="64" />
      <path d="M14 15v22c0 8 4 12 11 12s11-4 11-12V15h-7v21c0 4-1 6-4 6s-4-2-4-6V15h-7Z" fill="#0b1118" />
      <path d="M42 15h8v7h-8zM42 27h8v22h-8z" fill="#0b1118" />
    </svg>
  )
}

/**
 * Render the USI deployment name without its independently slotted mark.
 * @returns the USI wordmark.
 */
export function OfficialBrandName() {
  return <span aria-label="Unsuspicious Industries" style={{ fontWeight: 800, letterSpacing: '0.12em' }}>USI</span>
}
