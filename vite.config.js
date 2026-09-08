import { execSync } from 'node:child_process'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

function resolveBuildSha(){
  const explicit=process.env.COURSEFINDER_BUILD_SHA?.trim()
  if(explicit)return explicit
  try{return execSync('git rev-parse HEAD',{encoding:'utf8'}).trim()}catch{return'unknown'}
}

const buildSha=resolveBuildSha()

export default defineConfig({
  plugins:[
    react(),
    {
      name:'coursefinder-build-metadata',
      transformIndexHtml(){
        return [{tag:'meta',attrs:{name:'coursefinder-build-sha',content:buildSha},injectTo:'head'}]
      },
    },
  ],
  server:{port:5173},
})
