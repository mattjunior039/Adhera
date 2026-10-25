type ShellProps = {
  children: React.ReactNode
  className?: string
  innerClassName?: string
}

export function Shell({ children, className, innerClassName }: ShellProps) {
  return (
    <div className={`rounded-[28px] bg-ink/[0.03] p-1.5 ring-1 ring-line ${className ?? ''}`}>
      <div
        className={`rounded-[22px] bg-surface shadow-[inset_0_1px_0_rgba(255,255,255,0.8)] ${innerClassName ?? ''}`}
      >
        {children}
      </div>
    </div>
  )
}
