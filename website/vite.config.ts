import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // GitHub Pages serves the site from /<repository-name>/. Override with BASE_PATH for other hosts.
  base: process.env.BASE_PATH ?? '/PillBox/',
})
