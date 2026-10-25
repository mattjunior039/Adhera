import { useMemo, useRef } from 'react'
import { useFrame } from '@react-three/fiber'
import { useGLTF } from '@react-three/drei'
import * as THREE from 'three'

const MODEL_SCALE = 0.03
const OPEN_LIMIT = 0.9
const HOTSPOT_ANCHORS: Record<string, [number, number, number]> = {
  camera: [0, 1.12, -0.7],
  compartments: [-1.1, 0.86, 0],
  processor: [1.1, 0.72, 0.2],
  lights: [0, 0.52, 3.15],
  lid: [-2.95, 0.82, 0],
  power: [0, 0.37, -3.2],
}

type OrganizerModelProps = {
  lidOpen?: number
  autoLid?: boolean
  highlight?: string | null
  renderHotspot?: (id: string) => React.ReactNode
}

export function OrganizerModel({ lidOpen = 0, autoLid = false, highlight = null, renderHotspot }: OrganizerModelProps) {
  const closed = useGLTF(`${import.meta.env.BASE_URL}models/adhera-closed.glb`)
  const opened = useGLTF(`${import.meta.env.BASE_URL}models/adhera-open.glb`)
  const openness = useRef(lidOpen)

  const model = useMemo(() => {
    const scene = closed.scene.clone(true)
    scene.traverse((object) => {
      if (object instanceof THREE.Mesh) {
        object.castShadow = true
        object.receiveShadow = true
      }
    })
    return scene
  }, [closed.scene])

  const leftFlap = useMemo(() => model.getObjectByName('Flap_Left'), [model])
  const rightFlap = useMemo(() => model.getObjectByName('Flap_Right'), [model])

  const openAngles = useMemo(() => ({
    left: opened.scene.getObjectByName('Flap_Left')?.rotation.z ?? -Math.PI,
    right: opened.scene.getObjectByName('Flap_Right')?.rotation.z ?? Math.PI,
  }), [opened.scene])

  useFrame((state, delta) => {
    let target = lidOpen
    if (autoLid) {
      const phase = (state.clock.elapsedTime % 10) / 10
      target = phase < 0.16 ? phase / 0.16 : phase < 0.6 ? 1 : phase < 0.78 ? 1 - (phase - 0.6) / 0.18 : 0
      target *= OPEN_LIMIT
    }
    openness.current = THREE.MathUtils.damp(openness.current, target, 4, delta)
    if (leftFlap) leftFlap.rotation.z = -openAngles.left * openness.current
    if (rightFlap) rightFlap.rotation.z = -openAngles.right * openness.current
  })

  return <group>
    <group scale={MODEL_SCALE}><primitive object={model} /></group>
    {renderHotspot && Object.entries(HOTSPOT_ANCHORS).map(([id, position]) => (
      <group key={id} position={position}>
        {highlight === id && <mesh scale={0.1}><sphereGeometry args={[1, 16, 16]} /><meshBasicMaterial color="#1f6f5f" transparent opacity={0.18} depthWrite={false} /></mesh>}
        {renderHotspot(id)}
      </group>
    ))}
  </group>
}

useGLTF.preload(`${import.meta.env.BASE_URL}models/adhera-closed.glb`)
useGLTF.preload(`${import.meta.env.BASE_URL}models/adhera-open.glb`)
