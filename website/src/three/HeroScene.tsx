import { useRef } from 'react'
import { useFrame } from '@react-three/fiber'
import { Float } from '@react-three/drei'
import { useReducedMotion } from 'motion/react'
import * as THREE from 'three'
import { SceneCanvas } from './SceneCanvas'
import { Stage } from './Stage'
import { OrganizerModel } from './OrganizerModel'

function HeroRig({ children }: { children: React.ReactNode }) {
  const group = useRef<THREE.Group>(null)
  const reduced = useReducedMotion()

  useFrame((state, delta) => {
    if (!group.current) return
    group.current.position.x = state.size.width < 768 ? -1.25 : -2.2
    const baseY = reduced ? 0 : Math.sin(state.clock.elapsedTime * 0.25) * 0.35
    const targetY = baseY + state.pointer.x * 0.12
    const targetX = -state.pointer.y * 0.08
    const k = Math.min(1, delta * 2)
    group.current.rotation.y += (targetY - group.current.rotation.y) * k
    group.current.rotation.x += (targetX - group.current.rotation.x) * k
  })

  return <group ref={group} position={[-2.2, 0, 0]}>{children}</group>
}

export function HeroScene() {
  const reduced = useReducedMotion()

  return (
    <SceneCanvas
      className="h-full w-full"
      dpr={[1, 1.75]}
      camera={{ position: [12.5, 10.5, 16.5], fov: 34 }}
      onCreated={({ camera }) => camera.lookAt(0.45, 0.5, 0)}
      gl={{ alpha: true, antialias: true }}
      shadows
    >
      <Stage />
      <HeroRig>
        <Float speed={1.2} rotationIntensity={0.15} floatIntensity={0.3} floatingRange={[-0.1, 0.1]}>
          <OrganizerModel autoLid={!reduced} lidOpen={reduced ? 0.55 : 0} />
        </Float>
      </HeroRig>
    </SceneCanvas>
  )
}
