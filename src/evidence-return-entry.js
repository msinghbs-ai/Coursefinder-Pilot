function parse(){const raw=location.hash.replace(/^#/,'');const[route,query='']=raw.split('?');return{route,params:new URLSearchParams(query)}}
let generation=0
function render(){
  const current=++generation
  const{route,params}=parse()
  const existing=document.querySelector('[data-evidence-return-course]')
  if(route!=='evidence'){
    existing?.remove()
    return
  }
  const id=params.get('return_course_id')
  if(!id){existing?.remove();return}
  const attach=(attempt=0)=>{
    if(current!==generation)return
    const host=document.querySelector('.evidence-hero-actions')
    if(!host){if(attempt<40)setTimeout(()=>attach(attempt+1),50);return}
    let button=document.querySelector('[data-evidence-return-course]')
    if(!button){
      button=document.createElement('button')
      button.type='button'
      button.className='m-secondary'
      button.dataset.evidenceReturnCourse='1'
      button.textContent='← Back to Course'
      host.prepend(button)
    }
    button.onclick=()=>{location.hash=`#courses?id=${encodeURIComponent(id)}`}
  }
  attach()
}
addEventListener('hashchange',render)
if(document.readyState==='loading')addEventListener('DOMContentLoaded',render,{once:true});else render()
