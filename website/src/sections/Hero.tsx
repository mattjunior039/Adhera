import { motion, useReducedMotion } from 'motion/react'
import { ShaderGradient, ShaderGradientCanvas } from '@shadergradient/react'
import { Button } from '../components/Button'
import { HeroScene } from '../three/HeroScene'
import { hero, site } from '../content'

export function Hero() {
  const reduced = useReducedMotion()

  return (
    <section id="product" className="product-hero relative min-h-[100dvh] overflow-hidden px-5 md:px-8">
      <div className="hero-atmosphere pointer-events-none absolute inset-0">
        <ShaderGradientCanvas
          style={{ position: 'absolute', inset: 0 }}
          pointerEvents="none"
          pixelDensity={1.2}
          fov={45}
          lazyLoad
        >
          <ShaderGradient
            type="waterPlane"
            animate={reduced ? 'off' : 'on'}
            uSpeed={0.12}
            uStrength={1.6}
            uDensity={1.1}
            uFrequency={3.5}
            cDistance={3.2}
            cPolarAngle={90}
            lightType="3d"
            brightness={1.2}
            grain="on"
            color1="#e7ece8"
            color2="#f3f4f1"
            color3="#b9d6cb"
          />
        </ShaderGradientCanvas>
      </div>
      <div className="pointer-events-none absolute inset-x-0 bottom-0 h-40 bg-gradient-to-b from-transparent to-paper" />

      <div className="hero-layout relative mx-auto grid max-w-[1320px] grid-cols-12 items-center gap-10 pb-16 pt-32 md:pt-36 lg:pt-24">
        <div className="hero-copy col-span-12 lg:col-span-5">
          <p className="hero-kicker">Adhera / Smart pill organizer</p>
          <motion.h1
            initial={reduced ? false : { opacity: 0, y: 24, filter: 'blur(6px)' }}
            animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
            transition={{ duration: 0.9, ease: [0.22, 1, 0.36, 1], delay: 0.05 }}
            className="text-balance text-5xl font-medium leading-[1.02] tracking-[-0.035em] text-ink md:text-6xl xl:text-7xl"
          >
            {hero.headline.split(', ')[0]},<br /><span>{hero.headline.split(', ')[1]}</span>
          </motion.h1>
          <motion.p
            initial={reduced ? false : { opacity: 0, y: 24, filter: 'blur(6px)' }}
            animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
            transition={{ duration: 0.9, ease: [0.22, 1, 0.36, 1], delay: 0.15 }}
            className="mt-6 max-w-[42ch] text-lg leading-relaxed text-muted"
          >
            {hero.sub}
          </motion.p>
          <motion.div
            initial={reduced ? false : { opacity: 0, y: 24, filter: 'blur(6px)' }}
            animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
            transition={{ duration: 0.9, ease: [0.22, 1, 0.36, 1], delay: 0.25 }}
            className="mt-10 flex flex-wrap items-center gap-4"
          >
            <Button href={site.secondaryCta.href}>{site.secondaryCta.label}</Button>
            <Button href={site.primaryCta.href} variant="ghost">
              {site.primaryCta.label}
            </Button>
          </motion.div>
        </div>

        <div className="hero-object col-span-12 lg:col-span-7">
          <div className="relative aspect-[4/3] min-h-[420px] w-full lg:min-h-[640px]">
            <HeroScene />
          </div>
        </div>
      </div>
    </section>
  )
}
