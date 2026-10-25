import { ArrowUpRight } from '@phosphor-icons/react'

type ButtonProps = {
  href: string
  children: React.ReactNode
  variant?: 'primary' | 'ghost'
  onClick?: () => void
}

export function Button({ href, children, variant = 'primary', onClick }: ButtonProps) {
  if (variant === 'ghost') {
    return (
      <a
        href={href}
        onClick={onClick}
        className="secondary-link inline-flex items-center py-3.5 text-sm font-medium text-ink"
      >
        {children}
      </a>
    )
  }

  return (
    <a
      href={href}
      onClick={onClick}
      className="group inline-flex items-center whitespace-nowrap rounded-full bg-ink py-1.5 pl-6 pr-1.5 text-sm font-medium text-paper transition duration-500 ease-[cubic-bezier(0.32,0.72,0,1)] active:scale-[0.98]"
    >
      <span>{children}</span>
      <span className="ml-3 flex h-9 w-9 items-center justify-center rounded-full bg-paper/10 transition-transform duration-500 ease-[cubic-bezier(0.32,0.72,0,1)] group-hover:translate-x-0.5 group-hover:-translate-y-px group-hover:scale-105">
        <ArrowUpRight size={16} weight="light" />
      </span>
    </a>
  )
}
