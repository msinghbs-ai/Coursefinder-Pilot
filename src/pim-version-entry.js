const VERSION='2.14.2'
let attempts=0
function sync(){
  document.querySelectorAll('.m-brand-copy small,.m-login-version,.m-release-pill').forEach(el=>{
    const text=el.textContent||''
    if(/v2\.13(?:\.0)?/.test(text))el.textContent=text.replace(/v2\.13(?:\.0)?/,'v'+VERSION)
    else if(/v2\.14(?:\.0|\.1)?/.test(text))el.textContent=text.replace(/v2\.14(?:\.0|\.1)?/,'v'+VERSION)
  })
  attempts+=1
  if(attempts<20)setTimeout(sync,150)
}
if(document.readyState==='loading')addEventListener('DOMContentLoaded',sync,{once:true});else sync()
