import { useEffect, useState } from 'react'
import { AnimatePresence, motion, useMotionValueEvent, useScroll } from 'motion/react'
import { site } from '../content'

export function Nav() {
  const [open, setOpen] = useState(false)
  const [scrolled, setScrolled] = useState(false)
  const { scrollY } = useScroll()

  useMotionValueEvent(scrollY, 'change', (value) => {
    setScrolled(value > 40)
  })

  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : ''
    return () => {
      document.body.style.overflow = ''
    }
  }, [open])

  return (
    <>
      <header className="site-header fixed inset-x-0 top-4 z-50 flex justify-center px-5">
        <nav
          className={`site-nav flex h-14 max-w-fit items-center gap-6 rounded-full px-4 ring-1 ring-line backdrop-blur-xl transition-colors duration-500 shadow-[0_20px_50px_-30px_rgba(22,40,34,0.35)] ${
            scrolled ? 'bg-paper/90' : 'bg-paper/75'
          }`}
        >
          <a href="#product" className="brand-lockup" aria-label="Adhera, back to top">
            <span className="brand-symbol"><img src={`${import.meta.env.BASE_URL}brand/adhera-logo.png`} alt="" /></span>
            <span className="brand-name"><img src={`${import.meta.env.BASE_URL}brand/adhera-logo.png`} alt="" /></span>
          </a>

          <div className="hidden items-center gap-1 md:flex">
            {site.nav.map((item) => (
              <a
                key={item.href}
                href={item.href}
                className="rounded-full px-3.5 py-2 text-sm text-ink-2 transition-colors duration-300 hover:text-ink"
              >
                {item.label}
              </a>
            ))}
          </div>

          <div className="flex items-center gap-2">
            <a
              href={site.primaryCta.href}
              className="hidden rounded-full bg-ink px-4 py-2 text-sm font-medium text-paper transition-transform duration-300 hover:scale-[1.02] active:scale-[0.98] md:block"
            >
              {site.primaryCta.label}
            </a>
            <button
              type="button"
              aria-label={open ? 'Close menu' : 'Open menu'}
              aria-expanded={open}
              onClick={() => setOpen((value) => !value)}
              className="flex h-10 w-10 items-center justify-center rounded-full ring-1 ring-line md:hidden"
            >
              <span className="relative block h-3 w-4">
                <span
                  className={`absolute left-0 top-0 h-px w-full bg-ink transition-transform duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] ${
                    open ? 'translate-y-[5.5px] rotate-45' : ''
                  }`}
                />
                <span
                  className={`absolute left-0 top-[11px] h-px w-full bg-ink transition-transform duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] ${
                    open ? '-translate-y-[5.5px] -rotate-45' : ''
                  }`}
                />
              </span>
            </button>
          </div>
        </nav>
      </header>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
            className="fixed inset-0 z-40 bg-paper/95 backdrop-blur-2xl md:hidden"
          >
            <div className="flex h-full flex-col justify-center gap-1 px-8">
              {site.nav.map((item, index) => (
                <motion.a
                  key={item.href}
                  href={item.href}
                  onClick={() => setOpen(false)}
                  initial={{ opacity: 0, y: 16 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.5, ease: [0.22, 1, 0.36, 1], delay: 0.05 + index * 0.06 }}
                  className="py-3 text-3xl font-medium tracking-[-0.035em] text-ink"
                >
                  {item.label}
                </motion.a>
              ))}
              <motion.a
                href={site.primaryCta.href}
                onClick={() => setOpen(false)}
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{
                  duration: 0.5,
                  ease: [0.22, 1, 0.36, 1],
                  delay: 0.05 + site.nav.length * 0.06,
                }}
                className="mt-6 inline-flex w-fit rounded-full bg-ink px-6 py-3.5 text-base font-medium text-paper"
              >
                {site.primaryCta.label}
              </motion.a>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  )
}
