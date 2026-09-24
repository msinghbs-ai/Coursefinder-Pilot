// Builds public/release-history.json before every build (P7, 25 Sep 2026).
// One history from three sources, newest first, one entry per version:
//  1. docs/release-notes/v*.md          (authoritative for the releases they cover)
//  2. src/release-manifest.js RELEASE   (the current release)
//  3. src/pim-version-entry.js RELEASES (legacy hard-coded history, v2.15.78 and earlier)
import{readFileSync,readdirSync,writeFileSync,mkdirSync}from'node:fs'
const root=new URL('../',import.meta.url)
const read=p=>readFileSync(new URL(p,root),'utf8')
const cmp=(a,b)=>{const x=a.split('.').map(Number),y=b.split('.').map(Number);for(let i=0;i<Math.max(x.length,y.length);i++){const d=(y[i]||0)-(x[i]||0);if(d)return d}return 0}
function arrayLiteral(src,marker){const start=src.indexOf(marker);if(start<0)throw new Error(`${marker} not found`);let i=src.indexOf('[',start),depth=0,q=null
  for(let j=i;j<src.length;j++){const c=src[j];if(q){if(c==='\\'){j++;continue}if(c===q)q=null;continue}if(c==="'"||c==='"'||c==='`'){q=c;continue}if(c==='[')depth++;else if(c===']'){depth--;if(depth===0)return src.slice(i,j+1)}}throw new Error('unbalanced array')}
function objectLiteral(src,marker){const start=src.indexOf(marker);if(start<0)throw new Error(`${marker} not found`);let i=src.indexOf('{',start),depth=0,q=null
  for(let j=i;j<src.length;j++){const c=src[j];if(q){if(c==='\\'){j++;continue}if(c===q)q=null;continue}if(c==="'"||c==='"'||c==='`'){q=c;continue}if(c==='{')depth++;else if(c==='}'){depth--;if(depth===0)return src.slice(i,j+1)}}throw new Error('unbalanced object')}
const legacy=new Function(`return ${arrayLiteral(read('src/pim-version-entry.js'),'const RELEASES=')}`)()
const manifest=read('src/release-manifest.js')
const version=manifest.match(/export const UI_VERSION='([^']+)'/)[1]
const current={version,...new Function(`const UI_VERSION='${version}',PACKAGE_VERSION='';return ${objectLiteral(manifest,'export const RELEASE=')}`)()}
function fromMarkdown(text){const title=(text.match(/^# PIM Admin v([\d.]+)\s*[—-]\s*(.+)$/m)||[]);if(!title[1])return null
  const section=h=>{const m=text.split(/^## /m).find(s=>s.toLowerCase().startsWith(h));return m?m.split('\n').filter(l=>/^\s*-\s+/.test(l)).map(l=>l.replace(/^\s*-\s+/,'').trim()):[]}
  return{version:title[1],title:title[2].trim(),date:(text.match(/^Date:\s*(.+)$/m)||[])[1]?.trim()||'',changes:section("what's new"),bugFixes:section('bug')}}
const docs=readdirSync(new URL('docs/release-notes/',root)).filter(f=>/^v[\d.]+\.md$/.test(f)).map(f=>fromMarkdown(read(`docs/release-notes/${f}`))).filter(Boolean)
// Accepted releases recorded in the manifest (e.g. the v2.15.79 recovery release) carry their own notes.
const accepted=new Function(`return ${arrayLiteral(manifest,'export const ACCEPTED_RELEASES=')}`)().filter(r=>r&&r.version&&(r.title||r.changes))
const byVersion=new Map()
for(const r of legacy)byVersion.set(r.version,{version:r.version,date:r.date||'',title:r.title||'',changes:r.changes||[],bugFixes:r.bugFixes||[],source:'legacy'})
for(const r of accepted)byVersion.set(r.version,{version:r.version,date:r.date||'',title:r.title||'',changes:r.changes||[],bugFixes:r.bugFixes||[],source:'manifest-accepted'})
for(const r of docs)byVersion.set(r.version,{...r,source:'docs'})
byVersion.set(current.version,{version:current.version,date:current.date,title:current.title,changes:current.changes||[],bugFixes:current.bugFixes||[],source:'manifest'})
const releases=[...byVersion.values()].sort((a,b)=>cmp(a.version,b.version))
mkdirSync(new URL('public/',root),{recursive:true})
writeFileSync(new URL('public/release-history.json',root),JSON.stringify({current:version,count:releases.length,releases},null,1)+'\n')
console.log(`release-history: ${releases.length} releases, current v${version}`)
