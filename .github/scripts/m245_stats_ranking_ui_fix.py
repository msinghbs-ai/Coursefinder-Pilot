from pathlib import Path
import re

p=Path('src/mature-main.jsx')
s=p.read_text()
s=s.replace("if(page==='Statistics & Rankings')return <StatisticsRankings onError={onError} navigate={navigate} rank={rank}/>","if(page==='Statistics & Rankings')return <StatisticsRankings onError={onError} navigate={navigate} rank={rank} routeParams={routeParams}/>")
start=s.index('function StatisticsRankings(')
end=s.index('\n\nfunction ProviderAssetsWorkspace',start)
new=r'''function StatisticsRankings({onError,navigate,rank,routeParams}){
 const[qilt,setQilt]=useState(null),[prisms,setPrisms]=useState(null),[ranking,setRanking]=useState(null),[busy,setBusy]=useState(true)
 const[rankingYears,setRankingYears]=useState({qs:[],the:[]}),[rankingSelection,setRankingSelection]=useState({qs:'',the:''})
 useEffect(()=>{let live=true;setBusy(true);Promise.all([
  api.qiltPage({limit:1,offset:0,sort:'year',direction:'desc'}).catch(e=>({error:e})),
  api.prismsPage({limit:1,offset:0,sort:'period',direction:'desc'}).catch(e=>({error:e})),
  api.rankingSummary().catch(e=>({error:e})),
  api.rankingFilters('qs_wur').catch(e=>({error:e})),
  api.rankingFilters('the_wur').catch(e=>({error:e}))
 ]).then(([q,p,r,qsf,thef])=>{if(!live)return;if(q?.error)onError?.(q.error.message);else setQilt(q);if(p?.error)onError?.(p.error.message);else setPrisms(p);if(r?.error)onError?.(r.error.message);else setRanking(r);const qy=(qsf?.years||[]).map(String),ty=(thef?.years||[]).map(String);setRankingYears({qs:qy,the:ty});setRankingSelection(x=>({qs:x.qs&&qy.includes(x.qs)?x.qs:(qy[0]||''),the:x.the&&ty.includes(x.the)?x.the:(ty[0]||'')}))}).finally(()=>live&&setBusy(false));return()=>{live=false}},[])
 const q=qilt?.items?.[0]||qilt?.rows?.[0]||null,p=prisms?.items?.[0]||prisms?.rows?.[0]||null
 const qYear=q?[q.collection_year_from,q.collection_year_to].filter(Boolean).join('–'):'—'
 const pPeriod=p?[p.period_start,p.period_end].filter(Boolean).map(x=>String(x).slice(0,10)).join(' → '):'—'
 const systems=ranking?.systems||[],qs=systems.find(x=>x.code==='qs_wur'),the=systems.find(x=>x.code==='the_wur')
 const activeDataset=routeParams?.get?.('dataset')||'',activeYear=routeParams?.get?.('year')||''
 useEffect(()=>{if(activeDataset==='qs_wur'&&activeYear&&rankingYears.qs.includes(String(activeYear)))setRankingSelection(x=>({...x,qs:String(activeYear)}));if(activeDataset==='the_wur'&&activeYear&&rankingYears.the.includes(String(activeYear)))setRankingSelection(x=>({...x,the:String(activeYear)}))},[activeDataset,activeYear,rankingYears.qs.join('|'),rankingYears.the.join('|')])
 const openRanking=(system,key)=>{const selected=rankingSelection[key]||rankingYears[key][0]||'';if(selected)navigate('Statistics & Rankings',{dataset:system,year:selected})}
 return <div className="m-page-stack">
  <section className="m-panel">
   <PanelTitle icon={BarChart3} title="Statistics & Rankings" subtitle="One verification workspace for contextual statistics, ranking editions, coverage and provenance."/>
   <div className="m-stats-grid">
    <article className="m-stats-card"><span>QILT</span><strong>{busy?'…':Number(qilt?.total||0).toLocaleString()}</strong><small>observations · latest period {qYear}</small><div><button onClick={()=>navigate('Outcomes (QILT)')}>Open dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
    <article className="m-stats-card"><span>PRISMS</span><strong>{busy?'…':Number(prisms?.total||0).toLocaleString()}</strong><small>observations · latest period {pPeriod}</small><div><button onClick={()=>navigate('Student Flow (PRISMS)')}>Open dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
    <article className="m-stats-card"><span>QS World University Rankings</span><div className="m-ranking-card-picker"><label>Edition<select aria-label="QS ranking edition" value={rankingSelection.qs||rankingYears.qs[0]||''} onChange={e=>setRankingSelection(x=>({...x,qs:e.target.value}))}>{rankingYears.qs.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label></div><strong>{rankingSelection.qs||qs?.latest_edition||'—'}</strong><small>{qs?.accepted_editions?`${Number(qs.observations||0).toLocaleString()} observations · ${Number(qs.mapped_observations||0).toLocaleString()} mapped`:'No accepted edition applied yet.'}</small><div><button disabled={!rankingYears.qs.length} onClick={()=>openRanking('qs_wur','qs')}>Open Dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
    <article className="m-stats-card"><span>Times Higher Education</span><div className="m-ranking-card-picker"><label>Edition<select aria-label="THE ranking edition" value={rankingSelection.the||rankingYears.the[0]||''} onChange={e=>setRankingSelection(x=>({...x,the:e.target.value}))}>{rankingYears.the.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label></div><strong>{rankingSelection.the||the?.latest_edition||'—'}</strong><small>{the?.accepted_editions?`${Number(the.observations||0).toLocaleString()} observations · ${Number(the.mapped_observations||0).toLocaleString()} mapped`:'No accepted edition applied yet.'}</small><div><button disabled={!rankingYears.the.length} onClick={()=>openRanking('the_wur','the')}>Open Dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
   </div>
  </section>
  {['qs_wur','the_wur'].includes(activeDataset)&&<RankingDatasetPanel system={activeDataset} year={activeYear} navigate={navigate} onError={onError}/>} 
  <section className="m-panel">
   <div className="m-stats-section-head"><div><h3>Coverage & verification</h3><p>Use dataset drill-downs to inspect exact observations. Ranking coverage, edition filters, Provider mapping and Evidence remain publisher-specific.</p></div><button className="m-secondary" onClick={()=>navigate('Compare',{type:'provider'})}><ArrowLeftRight size={15}/>Open Compare</button></div>
   <div className="m-stats-notes">
    <div><b>Provider context</b><span>QILT, PRISMS and institutional rankings retain their native source grain.</span></div>
    <div><b>Years / editions</b><span>QS and THE use independent edition selectors; Compare retains its own per-ranking edition controls.</span></div>
    <div><b>Evidence</b><span>Every accepted observation remains traceable to governed source Evidence.</span></div>
    <div><b>Historical publisher files</b><span>{rank>=4?'Ranking import management is available only through Administration → Sources & Imports.':'Import controls are restricted to authorised operator roles.'}</span></div>
   </div>
  </section>
 </div>
}

function RankingDatasetPanel({system,year,navigate,onError}){
 const[filters,setFilters]=useState(null),[data,setData]=useState(null),[query,setQuery]=useState(''),[offset,setOffset]=useState(0),[sort,setSort]=useState('rank'),[direction,setDirection]=useState('asc'),[busy,setBusy]=useState(false)
 const debounced=useDebounce(query,260),label=system==='qs_wur'?'QS World University Rankings':'Times Higher Education'
 useEffect(()=>{let live=true;api.rankingFilters(system).then(x=>live&&setFilters(x)).catch(e=>onError?.(e.message));return()=>{live=false}},[system])
 const years=(filters?.years||[]).map(String),selectedYear=years.includes(String(year))?String(year):(years[0]||String(year||''))
 useEffect(()=>{setOffset(0)},[system,selectedYear,debounced,sort,direction])
 useEffect(()=>{let live=true;if(!system||!selectedYear)return;setBusy(true);api.rankingObservations({limit:50,offset,query:debounced,systemCode:system,editionYear:selectedYear,sort,direction}).then(x=>live&&setData(x)).catch(e=>onError?.(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[system,selectedYear,debounced,offset,sort,direction])
 const rows=data?.items||[],total=Number(data?.total||0)
 const sortHead=(key,title)=><button type="button" onClick={()=>{if(sort===key)setDirection(x=>x==='asc'?'desc':'asc');else{setSort(key);setDirection('asc')}}}>{title}{sort===key?(direction==='asc'?' ↑':' ↓'):''}</button>
 return <section className="m-panel" data-react-ranking-viewer="1">
  <div className="m-workspace-head"><div><div className="m-section-kicker">Imported ranking dataset</div><h2>{label}</h2><p>Accepted Layer 1 observations for the selected edition. Publisher institution identity remains distinct from canonical Provider mapping.</p></div><label className="m-ranking-dataset-edition">Edition<select aria-label={`${label} dataset edition`} value={selectedYear} onChange={e=>navigate('Statistics & Rankings',{dataset:system,year:e.target.value})}>{years.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label></div>
  <div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search publisher institution or mapped Provider…"/>{query&&<button onClick={()=>setQuery('')}><X size={14}/></button>}</label></div>
  <div className="dense-table-wrap"><table className="dense-table m-fluid-table"><thead><tr><th>{sortHead('institution','Publisher institution')}</th><th>{sortHead('provider','Canonical Provider')}</th><th>{sortHead('rank','Rank')}</th><th>{sortHead('score','Overall score')}</th><th>{sortHead('country','Country')}</th><th><span>Evidence</span></th></tr></thead><tbody>{rows.length?rows.map((x,i)=><tr key={`${x.publisher_institution_name||i}-${x.rank_display||x.rank_exact||''}`}><td className="primary-cell">{x.publisher_institution_name||'—'}<small style={{display:'block',color:'#94a3b8'}}>{x.ranking_name||label}</small></td><td>{x.provider_name||'Unmapped'}</td><td>{x.rank_display||x.rank_exact||'—'}</td><td>{x.overall_score==null?'—':x.overall_score}</td><td>{x.country_text||'—'}</td><td>{x.evidence_artifact_id?<button className="m-secondary compact" onClick={()=>navigate('Evidence',{id:x.evidence_artifact_id})}>Open Evidence</button>:'—'}</td></tr>):<tr><td colSpan="6"><EmptyInline text={busy?'Loading ranking observations…':'No accepted observations match this edition and search.'}/></td></tr>}</tbody></table></div>
  <Pager offset={offset} limit={50} total={total} onOffset={setOffset}/>
 </section>
}
'''
s=s[:start]+new+s[end:]
p.write_text(s)

idx=Path('index.html')
t=idx.read_text()
t=t.replace('<script type="module" src="/src/RankingDatasetViewer.js"></script>','')
idx.write_text(t)

Path('tests/uat/m245-stats-ranking-ui-fix.spec.mjs').write_text("""import{test,expect}from'@playwright/test'\nimport fs from'node:fs'\nconst shell=()=>fs.readFileSync('src/mature-main.jsx','utf8')\ntest('Statistics ranking cards expose independent edition selectors and no import controls',()=>{const s=shell(),a=s.indexOf('function StatisticsRankings('),b=s.indexOf('function RankingDatasetPanel(',a),block=s.slice(a,b);expect(block).toContain('aria-label=\\\"QS ranking edition\\\"');expect(block).toContain('aria-label=\\\"THE ranking edition\\\"');expect(block).not.toContain('Manage imports');expect(block).not.toContain("section:'sources-imports'")})\ntest('Open Dataset is a native React route with selected publisher edition',()=>{const s=shell();expect(s).toContain("navigate('Statistics & Rankings',{dataset:system,year:selected})");expect(s).toContain('function RankingDatasetPanel({system,year,navigate,onError})');expect(s).toContain("api.rankingObservations({limit:50,offset,query:debounced,systemCode:system,editionYear:selectedYear,sort,direction})");const index=fs.readFileSync('index.html','utf8');expect(index).not.toContain('/src/RankingDatasetViewer.js')})\n""")
