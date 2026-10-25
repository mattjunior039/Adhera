import { DeviceMobile, Package } from '@phosphor-icons/react'
import { Reveal } from '../components/Reveal'
import { Shell } from '../components/Shell'
import { StillScene } from '../three/StillScene'
import { introducing } from '../content'

export function Introducing() {
  return (
    <section id="introducing" className="relative px-5 py-24 md:px-8 md:py-36">
      <div className="mx-auto grid max-w-[1320px] grid-cols-12 items-center gap-10 lg:gap-16">
        <Reveal className="col-span-12 lg:col-span-7">
          <Shell>
            <div className="h-[420px] lg:h-[520px]">
              <StillScene />
            </div>
          </Shell>
        </Reveal>

        <div className="col-span-12 lg:col-span-5">
          <Reveal>
            <h2 className="text-4xl font-medium leading-[1.05] tracking-[-0.035em] text-ink md:text-6xl">
              {introducing.heading}
            </h2>
          </Reveal>
          <Reveal delay={0.1}>
            <p className="mt-6 max-w-[60ch] leading-relaxed text-muted">{introducing.body}</p>
          </Reveal>

          <div className="mt-10">
            {introducing.parts.map((part, index) => (
              <Reveal key={part.title} delay={0.15 + index * 0.1}>
                <div className={`flex gap-5 py-6 ${index > 0 ? 'border-t border-line' : ''}`}>
                  <span className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-accent-soft text-accent">
                    {index === 0 ? (
                      <Package size={20} weight="light" />
                    ) : (
                      <DeviceMobile size={20} weight="light" />
                    )}
                  </span>
                  <div>
                    <h3 className="text-lg font-medium text-ink">{part.title}</h3>
                    <p className="mt-1.5 max-w-[52ch] leading-relaxed text-muted">{part.body}</p>
                  </div>
                </div>
              </Reveal>
            ))}
          </div>

          <Reveal delay={0.3}>
            <p className="mt-8 border-l-2 border-accent pl-4 text-sm leading-relaxed text-ink-2">
              {introducing.positioning}
            </p>
          </Reveal>
        </div>
      </div>
    </section>
  )
}
