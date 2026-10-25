import { useState } from 'react'
import { AnimatePresence, motion } from 'motion/react'
import { Camera, Cpu, Lightbulb, Magnet, Plug, SquaresFour, type Icon } from '@phosphor-icons/react'
import { Reveal } from '../components/Reveal'
import { Shell } from '../components/Shell'
import { ExplorerScene } from '../three/ExplorerScene'
import { explorer } from '../content'

const HOTSPOT_ICONS: Record<string, Icon> = {
  camera: Camera,
  compartments: SquaresFour,
  processor: Cpu,
  lights: Lightbulb,
  lid: Magnet,
  power: Plug,
}

export function Explorer() {
  const [active, setActive] = useState('camera')

  return (
    <section id="technology" className="relative px-5 py-24 md:px-8 md:py-36">
      <div className="mx-auto max-w-[1320px]">
        <Reveal>
          <h2 className="text-4xl font-medium leading-[1.05] tracking-[-0.035em] text-ink md:text-6xl">
            {explorer.heading}
          </h2>
        </Reveal>
        <Reveal delay={0.1}>
          <p className="mt-5 max-w-[60ch] leading-relaxed text-muted">{explorer.sub}</p>
        </Reveal>

        <div className="mt-14 grid grid-cols-12 gap-10 lg:gap-16">
          <Reveal className="col-span-12 lg:col-span-8">
            <Shell innerClassName="bg-paper-2">
              <div className="h-[560px] lg:h-[680px]">
                <ExplorerScene active={active} onSelect={setActive} />
              </div>
            </Shell>
          </Reveal>

          <div className="col-span-12 lg:col-span-4">
            <div className="flex flex-col">
              {explorer.hotspots.map((hotspot) => {
                const Icon = HOTSPOT_ICONS[hotspot.id]
                const isActive = active === hotspot.id
                return (
                  <motion.div key={hotspot.id} layout className="border-t border-line">
                    <button
                      type="button"
                      onClick={() => setActive(hotspot.id)}
                      className="flex w-full items-center gap-4 py-5 text-left"
                    >
                      <span
                        className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-full transition-colors duration-300 ${
                          isActive ? 'bg-ink text-paper' : 'bg-accent-soft text-accent'
                        }`}
                      >
                        <Icon size={20} weight="light" />
                      </span>
                      <span
                        className={`text-base font-medium transition-colors duration-300 ${
                          isActive ? 'text-ink' : 'text-ink-2'
                        }`}
                      >
                        {hotspot.title}
                      </span>
                    </button>
                    <AnimatePresence initial={false}>
                      {isActive && (
                        <motion.p
                          key="body"
                          initial={{ opacity: 0, y: -6 }}
                          animate={{ opacity: 1, y: 0 }}
                          exit={{ opacity: 0, y: -6 }}
                          transition={{ duration: 0.35, ease: [0.22, 1, 0.36, 1] }}
                          className="max-w-[46ch] pb-6 pl-14 leading-relaxed text-muted"
                        >
                          {hotspot.body}
                        </motion.p>
                      )}
                    </AnimatePresence>
                  </motion.div>
                )
              })}
              <div className="border-t border-line" />
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
