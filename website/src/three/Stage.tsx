import { ContactShadows, Environment, Lightformer } from '@react-three/drei'

export function Stage() {
  return (
    <>
      <Environment resolution={256} frames={1}>
        <Lightformer form="rect" intensity={2.2} position={[0, 6, 0]} rotation-x={Math.PI / 2} scale={[12, 6, 1]} />
        <Lightformer form="rect" intensity={1.1} position={[-7, 2, 2]} rotation-y={Math.PI / 2} scale={[8, 3, 1]} />
        <Lightformer form="rect" intensity={0.8} position={[7, 2, -2]} rotation-y={-Math.PI / 2} scale={[8, 3, 1]} />
        <Lightformer form="rect" intensity={0.6} color="#dde9e4" position={[0, 1, 8]} scale={[10, 2, 1]} />
      </Environment>
      <directionalLight
        position={[5, 9, 6]}
        intensity={1.4}
        castShadow
        shadow-mapSize-width={2048}
        shadow-mapSize-height={2048}
        shadow-camera-near={1}
        shadow-camera-far={25}
        shadow-camera-left={-8}
        shadow-camera-right={8}
        shadow-camera-top={8}
        shadow-camera-bottom={-8}
        shadow-bias={-0.0004}
      />
      <ambientLight intensity={0.35} />
      <ContactShadows position={[0, 0.001, 0]} opacity={0.4} blur={2.4} far={3} color="#1d2a26" scale={16} resolution={1024} />
    </>
  )
}
