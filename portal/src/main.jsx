import React from 'react'
import { createRoot } from 'react-dom/client'
import App from './App.jsx'
import './styles.css'
import { installChunkReloadGuard } from './lib/chunkReload.js'

installChunkReloadGuard() // s1203: a tab left open across a deploy reloads once instead of breaking

createRoot(document.getElementById('root')).render(<App />)
