// CF-247 (16 Oct 2026): database and file storage sizes, recorded daily. Platform Admin 23:18: "Prepare and record all db and tables data
// and sizes also prepare total bucket usage. Keep the stat's simple and recoed on daily basis". Reads admin_storage_sizes (rank 4+); Measure
// now is admin_storage_sizes_measure (Platform Admin). Recorded daily by job storage-size-daily (pipeline.storage_size_daily).
import React,{useEffect,useMemo,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,Metric,fmtNumber}from'./ui-kit'
import{fmtBytes,fmtDateTime}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const change=(now,before)=>{if(before==null||now==null)return'—';const d=now-before;return d===0?'no change':`${d>0?'+':'−'}${fmtBytes(Math.abs(d))}`}

export default function StorageSizes({onError}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false),[q,setQ]=useState(''),[all,setAll]=useState(false)
  const load=()=>supabase.rpc('admin_storage_sizes',{p_days:30}).then(({data,error})=>{if(error)throw error;setD(data)}).catch(e=>onError?.(errText(e)))
  useEffect(()=>{load()},[])
  const measure=async()=>{setBusy(true);try{const{error}=await supabase.rpc('admin_storage_sizes_measure');if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const tables=useMemo(()=>{const t=(d?.tables||[]).filter(x=>!q||x.name.toLowerCase().includes(q.toLowerCase()));return all||q?t:t.slice(0,25)},[d,q,all])
  if(!d)return <Loading label="Reading storage sizes…"/>
  const buckets=d.buckets||[],bucketBytes=buckets.reduce((a,b)=>a+Number(b.bytes||0),0),bucketFiles=buckets.reduce((a,b)=>a+Number(b.files||0),0)
  const daily=d.daily||[],weekAgo=daily.find(x=>x.day<=new Date(new Date(d.day).getTime()-7*864e5).toISOString().slice(0,10))
  return <section className="m-panel" data-storage-sizes>
    <div className="m-workspace-head"><div><h2>Storage sizes</h2><p>Recorded every day at about 00:25 Melbourne time{d.measured_at?`; last measured ${fmtDateTime(d.measured_at)}`:''}.</p></div>
      {d.can_measure&&<Button compact onClick={measure} disabled={busy}><RefreshCw size={14}/> {busy?'Measuring…':'Measure now'}</Button>}</div>
    <div className="cf-metric-grid">
      <Metric label="Database" value={fmtBytes(d.database_bytes)} detail={weekAgo?`${change(d.database_bytes,weekAgo.database_bytes)} in 7 days`:'7-day change after a week of records'}/>
      <Metric label="File storage (all buckets)" value={fmtBytes(bucketBytes)} detail={`${fmtNumber(bucketFiles)} files`}/>
      <Metric label="Tables" value={fmtNumber((d.tables||[]).length)} detail={`in ${fmtNumber((d.schemas||[]).length)} schemas`}/>
    </div>
    <h3 className="sl-h4">By day</h3>
    <div className="cf-table-wrap"><table className="cf-table" data-storage-daily><thead><tr><th>Day</th><th>Database</th><th>File storage</th><th>Files</th></tr></thead>
      <tbody>{daily.map(x=><tr key={x.day}><td>{x.day}</td><td>{fmtBytes(x.database_bytes)}</td><td>{fmtBytes(x.bucket_bytes)}</td><td>{fmtNumber(x.bucket_files)}</td></tr>)}</tbody></table></div>
    <h3 className="sl-h4">Buckets</h3>
    <div className="cf-table-wrap"><table className="cf-table" data-storage-buckets><thead><tr><th>Bucket</th><th>Size</th><th>Files</th><th>Change in 7 days</th></tr></thead>
      <tbody>{buckets.map(b=><tr key={b.name}><td><code>{b.name}</code></td><td>{fmtBytes(b.bytes)}</td><td>{fmtNumber(b.files)}</td><td>{change(b.bytes,b.bytes_7d_ago)}</td></tr>)}</tbody></table></div>
    <h3 className="sl-h4">Schemas</h3>
    <div className="cf-table-wrap"><table className="cf-table" data-storage-schemas><thead><tr><th>Schema</th><th>Size</th><th>Of which indexes</th><th>Rows (estimate)</th></tr></thead>
      <tbody>{(d.schemas||[]).map(s=><tr key={s.name}><td><code>{s.name}</code></td><td>{fmtBytes(s.bytes)}</td><td>{fmtBytes(s.index_bytes)}</td><td>{fmtNumber(s.rows)}</td></tr>)}</tbody></table></div>
    <div className="pg-bar"><h3 className="sl-h4">Tables</h3><span className="pg-spacer"/><input className="fv-input" value={q} onChange={e=>setQ(e.target.value)} placeholder="Find a table" aria-label="Find a table"/>{!q&&<label className="fcc-only"><input type="checkbox" checked={all} onChange={e=>setAll(e.target.checked)}/> All {fmtNumber((d.tables||[]).length)} tables</label>}</div>
    <div className="cf-table-wrap"><table className="cf-table" data-storage-tables><thead><tr><th>Table</th><th>Size</th><th>Table</th><th>Indexes</th><th>Long values</th><th>Rows (estimate)</th><th>Change in 1 day</th><th>Change in 7 days</th></tr></thead>
      <tbody>{tables.map(t=><tr key={t.name}><td><code>{t.name}</code></td><td><strong>{fmtBytes(t.bytes)}</strong></td><td>{fmtBytes(t.table_bytes)}</td><td>{fmtBytes(t.index_bytes)}</td><td>{fmtBytes(t.toast_bytes)}</td><td>{fmtNumber(t.rows)}</td><td>{change(t.bytes,t.bytes_1d_ago)}</td><td>{change(t.bytes,t.bytes_7d_ago)}</td></tr>)}</tbody></table></div>
    <small className="sd-desc">Rows are the database's estimate (no table is counted row by row). Long values are text and JSON kept outside the table. Bucket sizes are the file sizes Supabase Storage records.</small>
  </section>
}
