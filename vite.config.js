import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// v2.15.217 (code split): libraries in their own long-cached files; screens used by one page load on demand (see mature-main.jsx).
export default defineConfig({
  plugins: [react()],
  server: { port: 5173 },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined
          if (/node_modules\/(react|react-dom|scheduler)\//.test(id)) return 'vendor-react'
          if (id.includes('@supabase')) return 'vendor-supabase'
          if (id.includes('lucide-react')) return 'vendor-icons'
          return 'vendor'
        },
      },
    },
  },
})
