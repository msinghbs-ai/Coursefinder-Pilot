const VERSION='2.15.0'
let attempts=0
function sync(){
  document.querySelectorAll('.m-brand-copy small').forEach(el=>{if(el.textContent!==`PIM Admin v${VERSION}`)el.textContent=`PIM Admin v${VERSION}`})
  document.querySelectorAll('.m-login-version').forEach(el=>{if(el.textContent!==`PIM Admin v${VERSION}`)el.textContent=`PIM Admin v${VERSION}`})
  document.querySelectorAll('.m-release-pill').forEach(el=>{if(el.textContent!==`v${VERSION}`)el.textContent=`v${VERSION}`})
  attempts+=1
  if(attempts<12)setTimeout(sync,150)
}
if(document.readyState==='loading')addEventListener('DOMContentLoaded',sync,{once:true});else sync()
