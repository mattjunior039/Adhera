import { useEffect, useRef, useState } from 'react'
import { Canvas, type CanvasProps } from '@react-three/fiber'

type SceneCanvasProps = CanvasProps & {
  className?: string
}

export function SceneCanvas({ children, className, ...props }: SceneCanvasProps) {
  const ref = useRef<HTMLDivElement>(null)
  const [visible, setVisible] = useState(true)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    const observer = new IntersectionObserver(
      (entries) => {
        setVisible(entries[0]?.isIntersecting ?? true)
      },
      { threshold: 0 },
    )
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  return (
    <div ref={ref} className={className}>
      <Canvas frameloop={visible ? 'always' : 'never'} {...props}>
        {children}
      </Canvas>
    </div>
  )
}
