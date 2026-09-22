import React,{useEffect,useState}from'react'
import{RefreshCw,CheckCircle2,XCircle,ShieldCheck}from'lucide-react'
import{adminRead}from'./lib/supabase'
import'./tuition-ai-control.css'

// CF-247: read-only model-profile qualification comparison for the
// provider_current_tuition_validation task class. Deliberately read-only —
// there is no "activate"/"set primary" action here. Unpausing a qualified
// profile for real execution is a separate, not-yet-designed gate (must
// compare the current runtime binding hash against the one recorded at
// qualification time, the same class of check layer3-work-interpret already
// enforces on the execution path) and must not be a one-click UI action
// until that gate exists.
export default function TuitionAiControl(){
  const[data,setData]=useState(null)
  const[error,setError]=useState('')
  const[loading,setLoading]=useState(true)
  const load=async()=>{
    setLoading(true);setError('')
    try{setData(await adminRead('tuition_ai'))}
    catch(e){setError(e?.message||String(e))}
    finally{setLoading(false)}
  }
  useEffect(()=>{load()},[])
  const profiles=data?.profiles||[]
  const money=v=>v==null?'—':`$${Number(v).toFixed(4)}`
  return <section className="tai-panel">
    <div className="tai-head">
      <div>
        <small>Layer 3 · Tuition Validation AI</small>
        <h3>Model qualification comparison</h3>
        <p>Each profile must independently pass the CF-247 candidate-bound benchmark before it can ever be considered for real execution. Passing here does not enable execution — profiles remain paused until a separate, deliberate activation gate exists.</p>
      </div>
      <button onClick={load} disabled={loading}><RefreshCw size={14}/>Refresh</button>
    </div>
    {error&&<div className="tai-error">{error}</div>}
    {!error&&!loading&&!profiles.length&&<div className="tai-empty">No tuition validation profiles configured yet.</div>}
    <div className="tai-grid">
      {profiles.map(p=>
        <article key={p.id} className={`tai-card${p.benchmark_pass?' tai-pass':''}${!p.enabled?' tai-disabled':''}`}>
          <header>
            <span className="tai-model">{p.model_identifier}</span>
            {p.benchmark_pass
              ?<span className="tai-badge tai-badge-pass"><CheckCircle2 size={13}/>Qualified</span>
              :<span className="tai-badge tai-badge-fail"><XCircle size={13}/>Not qualified</span>}
          </header>
          <p className="tai-summary">{p.benchmark_summary||'No benchmark run recorded.'}</p>
          <div className="tai-stats">
            <span><b>{money(p.estimated_cost_usd)}</b>last run</span>
            <span><b>{money(p.cost_ceiling_usd)}</b>ceiling</span>
            <span><b>{p.external_call_count??'—'}</b>calls</span>
          </div>
          <div className="tai-flags">
            <ShieldCheck size={13}/>
            <span>{!p.enabled?'Retired — disqualified':p.paused?'Paused (qualification alone never auto-activates execution)':'Active'}</span>
          </div>
        </article>
      )}
    </div>
  </section>
}
