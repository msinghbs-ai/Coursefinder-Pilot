// Settings › Backup & restore (v2.15.310, CF-247). Platform Admin, 22 Oct 2026 07:41: "Maintain daily unpublished providers as the sql
// script and report, incase someone by mistake enables them ... misc settings backup on daily basis and restore it, only by platform admin".
// A backup holds every provider's Published switch and every setting value (daily at 6:50 am Melbourne, by hand, and before every restore).
// Pick a backup to see what differs now (who changed it last), download it as a SQL file, or put it back: all, providers, settings or the
// rows ticked. Reads and writes: public.admin_settings_backup (Platform Admin only).
import React,{useEffect,useState}from'react'
import{DatabaseBackup,Download,RefreshCw,RotateCcw}from'lucide-react'
import{supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Empty,Loading,StatusChip,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_settings_backup',{p_action:action,p_args:args||{}});if(error)throw error;return data}
const KIND={daily:'Daily',manual:'By hand',before_restore:'Before a restore'}
const show=v=>v==null?'—':typeof v==='object'?JSON.stringify(v):String(v)

export default function SettingsBackup({onError}){
  const[list,setList]=useState(null),[id,setId]=useState(''),[busy,setBusy]=useState(false),[note,setNote]=useState('')
  const load=()=>call('list').then(d=>{setList(d);if(!id&&d?.backups?.length)setId(String((d.backups.find(b=>b.kind==='daily')||d.backups[0]).id))}).catch(e=>onError?.(errText(e)))
  useEffect(()=>{load()},[])
  const take=async()=>{setBusy(true);try{const r=await call('take',{});setNote(`Backup ${r.backup_id} taken.`);await load();setId(String(r.backup_id))}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!list)return <section className="m-panel"><Loading label="Loading backups…"/></section>
  const bs=list.backups||[]
  return <Card id="settings.backup" title="Backup & restore" icon={DatabaseBackup}
    subtitle={`Every morning at about 6:50 a copy is kept of each provider's Published switch and every setting value (kept ${fmtNumber(list.keep_days)} days). Pick a backup to see what has changed since, download it as a SQL file, or put it back. Only the Platform Admin can see and restore backups; a backup is taken before every restore.`}
    data-settings-backup>
    <div className="fc-actions"><Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button><Button compact onClick={take} disabled={busy}><DatabaseBackup size={14}/>Back up now</Button>{note&&<small className="sd-desc" role="status">{note}</small>}</div>
    {bs.length===0?<Empty text="No backup yet."/>:<div className="dq-table-wrap"><table className="dq-table" data-backup-list><thead><tr><th>Backup</th><th>Taken</th><th>Kind</th><th className="num">Published</th><th className="num">Unpublished</th><th className="num">Settings</th><th/></tr></thead>
      <tbody>{bs.slice(0,30).map(b=><tr key={b.id} className={String(b.id)===id?'is-selected':''}>
        <td>{b.id}{b.note&&<small>{b.note}</small>}</td><td><small>{fmtDateTime(b.taken_at)}{b.by?` · ${b.by}`:''}</small></td><td>{KIND[b.kind]||b.kind}</td>
        <td className="num">{fmtNumber(b.counts?.published)}</td><td className="num">{fmtNumber(b.counts?.unpublished)}</td><td className="num">{fmtNumber(b.counts?.settings)}</td>
        <td><Button compact onClick={()=>setId(String(b.id))}>{String(b.id)===id?'Shown':'Compare'}</Button></td></tr>)}</tbody></table></div>}
    {id&&<BackupDiff key={id} id={id} onError={onError} onDone={load}/>}
  </Card>
}

function BackupDiff({id,onError,onDone}){
  const[d,setD]=useState(null),[pick,setPick]=useState({}),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[msg,setMsg]=useState('')
  const load=()=>call('diff',{backup_id:id}).then(setD).catch(e=>onError?.(errText(e)))
  useEffect(()=>{load()},[id])
  if(!d)return <Loading compact/>
  const ps=d.providers||[],ss=d.settings||[]
  const toggle=k=>setPick(p=>({...p,[k]:!p[k]}))
  const chosen=Object.keys(pick).filter(k=>pick[k])
  const download=async()=>{try{const r=await call('script',{backup_id:id});const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([r.sql],{type:'text/plain'}));a.download=`studysearch-backup-${id}.sql`;a.click();URL.revokeObjectURL(a.href)}catch(e){onError?.(errText(e))}}
  const restore=async scope=>{
    const what=scope==='items'?`${chosen.length} chosen row(s)`:scope==='providers'?'every provider that differs':scope==='settings'?'every setting that differs':'everything that differs'
    if(!window.confirm(`Put back ${what} as in backup ${id}? A backup of the current state is taken first.`))return
    setBusy(true);try{
      const r=await call('restore',{backup_id:id,scope,reason:reason.trim(),providers:chosen.filter(k=>k.startsWith('p:')).map(k=>k.slice(2)),settings:chosen.filter(k=>k.startsWith('s:')).map(k=>k.slice(2))})
      setMsg(`Put back ${r.providers} provider(s) and ${r.settings} setting(s)${r.archived_not_published?`; ${r.archived_not_published} archived provider(s) left unpublished`:''}. Backup ${r.before_restore} holds the state before.`)
      setPick({});setReason('');await load();onDone?.()
    }catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const can=reason.trim().length>=10&&!busy
  return <div className="plan-run" data-backup-diff>
    <h3 className="sd-subhead">Backup {id}: what differs now</h3>
    <p className="sd-desc">{fmtNumber(ps.length)} provider(s) and {fmtNumber(ss.length)} setting(s) differ from this backup.{d.new_providers?` ${fmtNumber(d.new_providers)} provider(s) were added since (not in the backup).`:''}{d.new_settings?` ${fmtNumber(d.new_settings)} setting(s) were added since.`:''}</p>
    <div className="fc-actions"><Button compact onClick={download}><Download size={14}/>Download SQL file</Button></div>
    {ps.length>0&&<div className="dq-table-wrap"><table className="dq-table" data-backup-providers><thead><tr><th/><th>Provider</th><th>In the backup</th><th>Now</th><th>Last changed</th></tr></thead>
      <tbody>{ps.map(p=><tr key={p.id}><td><input type="checkbox" aria-label={`Choose ${p.name}`} checked={!!pick['p:'+p.id]} onChange={()=>toggle('p:'+p.id)}/></td>
        <td><strong>{p.name}</strong><small>{p.country}{p.lifecycle_status!=='active'?` · ${p.lifecycle_status}`:''}</small></td>
        <td>{p.then_status}</td><td><StatusChip value={p.now_status} tone={p.now_status==='published'?'warning':'neutral'} label={p.now_status}/></td>
        <td><small>{p.last_change?`${fmtDateTime(p.last_change.at)} · ${p.last_change.by}`:'—'}</small></td></tr>)}</tbody></table></div>}
    {ss.length>0&&<div className="dq-table-wrap"><table className="dq-table" data-backup-settings><thead><tr><th/><th>Setting</th><th>In the backup</th><th>Now</th><th>Last changed</th></tr></thead>
      <tbody>{ss.map(s=>{const k=`s:${s.toolset_key}/${s.key}`;return <tr key={k}><td><input type="checkbox" aria-label={`Choose ${s.label}`} checked={!!pick[k]} onChange={()=>toggle(k)}/></td>
        <td><strong>{s.label||s.key}</strong><small>{s.section||s.toolset_key} · {s.key}</small></td><td><code>{show(s.then_value)}</code></td><td><code>{show(s.now_value)}</code></td>
        <td><small>{s.updated_at?fmtDateTime(s.updated_at):''}{s.updated_by?` · ${s.updated_by}`:''}{s.reason?` · ${s.reason}`:''}</small></td></tr>})}</tbody></table></div>}
    {(ps.length>0||ss.length>0)&&<div className="fc-actions">
      <input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Reason to put back (at least 10 characters)" aria-label="Reason"/>
      <Button compact onClick={()=>restore('items')} disabled={!can||chosen.length===0}><RotateCcw size={14}/>Put back chosen ({chosen.length})</Button>
      {ps.length>0&&<Button compact onClick={()=>restore('providers')} disabled={!can}><RotateCcw size={14}/>Put back all providers</Button>}
      {ss.length>0&&<Button compact onClick={()=>restore('settings')} disabled={!can}><RotateCcw size={14}/>Put back all settings</Button>}
      {msg&&<small className="sd-desc" role="status">{msg}</small>}</div>}
    {ps.length===0&&ss.length===0&&<Empty text="Nothing differs from this backup."/>}
  </div>
}
