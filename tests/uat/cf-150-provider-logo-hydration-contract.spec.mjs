// Guards: CF-150 de-duplicates Provider logo requests and removes reset hydration loop
import{readFileSync}from'node:fs'
import{test,expect}from'@playwright/test'

const src=readFileSync(new URL('../../src/ProviderLogo.jsx',import.meta.url),'utf8')
const release=readFileSync(new URL('../../src/ReleaseNotes.jsx',import.meta.url),'utf8') // v2.15.291: replaces release-currentness-entry.js
const index=readFileSync(new URL('../../index.html',import.meta.url),'utf8')

test('CF-150 de-duplicates Provider logo requests and removes reset hydration loop',()=>{
 expect(src).toContain('const inflight=new Map()')
 expect(src).toContain('if(inflight.has(key))return inflight.get(key)')
 expect(src).toContain("supabase.functions.invoke('provider-asset-access',{body:{stable_keys:keys}})")
 expect(src).toContain("img.loading='lazy'")
 expect(src).toContain("img.fetchPriority='low'")
 expect(src).toContain('requestAnimationFrame')
 expect(src).toContain('relevantMutation(records)')
 expect(src).toContain("document.getElementById('root')||document.body")
 expect(src).not.toContain('setTimeout(()=>{decorateProviderList();enableProviderLogoUpload()},90)')
 expect(src).not.toContain('new MutationObserver(queueDecorate).observe(document.documentElement')
})

test('CF-150 preserves Provider logo management and release currentness',()=>{
 expect(src).toContain("supabase.functions.invoke('provider-asset-upload'")
 expect(src).toContain('coursefinder:provider-logo-refresh')
 expect(src).toContain("supabase.rpc('admin_provider_logo_capability')") // CF-247 15 Oct 2026: who may change logos is a setting (was rank 5)
 // 7 Oct 2026: version pins moved to release-manifest.js (its own contract); the page title carries no version.
 expect(index).toContain('<title>StudySearch PIM Admin</title>')
 expect(release).toContain("from'./release-manifest.js'")
})
