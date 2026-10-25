import { useState } from 'react'
import { Html, OrbitControls } from '@react-three/drei'
import { useReducedMotion } from 'motion/react'
import { SceneCanvas } from './SceneCanvas'
import { Stage } from './Stage'
import { OrganizerModel } from './OrganizerModel'
import { explorer } from '../content'

type ExplorerSceneProps = {
  active: string | null
  onSelect: (id: string) => void
}

export function ExplorerScene({ active, onSelect }: ExplorerSceneProps) {
  const [interacted, setInteracted] = useState(false)
  const reduced = useReducedMotion()

  return (
    <SceneCanvas
      className="h-full w-full"
      dpr={[1, 1.75]}
      camera={{ position: [14, 11, 17], fov: 38 }}
      onCreated={({ camera }) => camera.lookAt(0, 0.5, 0)}
      gl={{ alpha: true, antialias: true }}
      shadows
    >
      <Stage />
      <OrganizerModel
        lidOpen={0.9}
        highlight={active}
        renderHotspot={(id) => {
          const hotspot = explorer.hotspots.find((item) => item.id === id)
          const isActive = active === id
          return (
            <Html center distanceFactor={8} zIndexRange={[20, 0]}>
              <button
                type="button"
                onClick={() => onSelect(id)}
                aria-label={hotspot?.title}
                className={`group relative flex h-7 w-7 items-center justify-center rounded-full ring-1 ring-line backdrop-blur-sm transition-colors duration-300 ${
                  isActive ? 'bg-ink' : 'bg-paper/90 hover:bg-surface'
                }`}
              >
                <span className={`h-1.5 w-1.5 rounded-full ${isActive ? 'bg-accent-soft' : 'bg-accent'}`} />
                <span className="pointer-events-none absolute left-1/2 top-full mt-2 -translate-x-1/2 whitespace-nowrap rounded-full bg-ink px-3 py-1 text-xs font-medium text-paper opacity-0 transition-opacity duration-200 group-hover:opacity-100">
                  {hotspot?.title}
                </span>
              </button>
            </Html>
          )
        }}
      />
      <OrbitControls
        target={[0, 0.5, 0]}
        enableZoom
        enablePan={false}
        minDistance={12}
        maxDistance={30}
        minPolarAngle={0.4}
        maxPolarAngle={1.35}
        autoRotate={!interacted && !reduced}
        autoRotateSpeed={0.6}
        enableDamping
        dampingFactor={0.08}
        onStart={() => setInteracted(true)}
      />
    </SceneCanvas>
  )
}
