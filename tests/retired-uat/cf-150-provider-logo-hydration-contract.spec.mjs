import{readFileSync}from'node:fs'
import{test,expect}from'@playwright/test'

const src=readFileSync(new URL('../../src/ProviderLogo.jsx',import.meta.url),'utf8')
const release=readFileSync(new URL('../../src/release-currentness-entry.js',import.meta.url),'utf8')
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
 expect(src).toContain('rank<5')
 expect(release).toContain("const VERSION='2.15.60'")
 expect(index).toContain('Coursefinder PIM Admin v2.15.60')
})
