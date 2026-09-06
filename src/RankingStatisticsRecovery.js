import{api}from'./lib/supabase'

const SYSTEMS={
 qs_wur:{label:'QS World University Rankings'},
 the_wur:{label:'Times Higher Education'},
}
const cache=new Map()
const esc=s=>String(s??'').replace(/[&<>\"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;'}[m]))
function yearsOf(value){
 const editions=Array.isArray(value?.editions)?value.editions:[]
 const raw=Array.isArray(value?.years)?value.years:editions.map(x=>x?.year??x?.edition_year)
 return [...new Set(raw.map(String).filter(Boolean))].sort((a,b)=>Number(b)-Number(a))
}
function cardFor(label){return [...document.querySelectorAll('.m-stats-card')].find(c=>String(c.querySelector(':scope>span')?.textContent||c.textContent||'').toLowerCase().includes(label.toLowerCase()))||null}
async function filters(system){if(!cache.has(system))cache.set(system,api.rankingFilters(system).catch(()=>({})));return cache.get(system)}
function openDataset(system,year){
 const hook=globalThis.__cfOpenRankingDataset
 if(typeof hook==='function'){hook(system,year);return}
 const p=new URLSearchParams();p.set('dataset',system);if(year)p.set('year',year);location.hash='#statistics-rankings?'+p.toString()
}
async function enhance(system,config){
 const card=cardFor(config.label);if(!card)return false
 const actions=card.querySelector(':scope>div');if(!actions)return false
 const f=await filters(system),years=yearsOf(f),editions=Array.isArray(f?.editions)?f.editions:[]
 if(!years.length)return false
 let picker=card.querySelector('.cf-ranking-card-picker')
 if(!picker){picker=document.createElement('label');picker.className='cf-ranking-card-picker';picker.innerHTML='Dataset / edition <select aria-label="Ranking dataset edition"></select>';actions.prepend(picker)}
 const select=picker.querySelector('select'),current=select.value
 select.innerHTML=years.map((y,i)=>`<option value="${esc(y)}">${esc(y)}${i===0?' · latest':''}</option>`).join('')
 select.value=years.includes(current)?current:years[0]
 const headline=card.querySelector(':scope>strong'),detail=card.querySelector(':scope>small')
 const render=()=>{const e=editions.find(x=>String(x?.year??x?.edition_year)===String(select.value));if(headline)headline.textContent=select.value;if(detail&&e)detail.textContent=`${Number(e.observations||0).toLocaleString()} observations · ${Number(e.mapped_observations||0).toLocaleString()} mapped`}
 select.onchange=render;render()
 ;[...actions.querySelectorAll('button')].filter(b=>/manage imports/i.test(b.textContent||'')).forEach(b=>b.remove())
 let open=[...actions.querySelectorAll('button')].find(b=>/open dataset/i.test(b.textContent||''))
 if(!open){open=document.createElement('button');open.textContent='Open dataset';actions.prepend(open)}
 open.onclick=()=>openDataset(system,select.value)
 card.dataset.rankingEditionRecovery='1'
 return true
}
async function run(){if(!location.hash.startsWith('#statistics-rankings'))return;for(const [system,config]of Object.entries(SYSTEMS))await enhance(system,config)}
let attempts=0
function schedule(){attempts=0;const id=setInterval(()=>{run().catch(()=>{});attempts+=1;if(attempts>=30)clearInterval(id)},500);run().catch(()=>{})}
if(typeof document!=='undefined'){document.readyState==='loading'?document.addEventListener('DOMContentLoaded',schedule,{once:true}):schedule();addEventListener('hashchange',schedule)}
