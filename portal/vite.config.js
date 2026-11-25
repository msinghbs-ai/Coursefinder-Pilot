import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// StudySearch Portal (s1140): its own app and Worker, separate from the Admin app in the repository root.
export default defineConfig({
  plugins: [react()],
  server: { port: 5174 },
})
