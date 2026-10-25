import { useRef } from 'react'
import { useFrame } from '@react-three/fiber'
import { useReducedMotion } from 'motion/react'
import * as THREE from 'three'
import { SceneCanvas } from './SceneCanvas'
import { Stage } from './Stage'
import { OrganizerModel } from './OrganizerModel'

function SlowYaw({ children }: { children: React.ReactNode }) {
  const group = useRef<THREE.Group>(null)
  const reduced = useReducedMotion()

  useFrame((state) => {
    if (!group.current) return
    if (!reduced) {
      group.current.rotation.y = Math.sin(state.clock.elapsedTime * 0.12) * 0.3
    }
  })

  return <group ref={group}>{children}</group>
}

export function StillScene() {
  return (
    <SceneCanvas
      className="h-full w-full"
      dpr={[1, 1.75]}
      camera={{ position: [12, 12, 16], fov: 36 }}
      onCreated={({ camera }) => camera.lookAt(0, 0.5, 0)}
      gl={{ alpha: true, antialias: true }}
      shadows
    >
      <Stage />
      <SlowYaw>
        <OrganizerModel lidOpen={0.9} />
      </SlowYaw>
    </SceneCanvas>
  )
}
