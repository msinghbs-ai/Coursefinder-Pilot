import React,{useEffect,useMemo,useState}from'react'
import{AlertTriangle,CheckCircle2,Database,KeyRound,RefreshCw,ServerCog,ShieldCheck}from'lucide-react'
import{adminRead,supabase}from'./lib/supabase'
import'./environment-migration.css'

const human=v=>String(v||'').replaceAll('_',' ').replace(/\b\w/g,c=>c.toUpperCase())
const fmt=v=>Number(v||0).toLocaleString()

export default function EnvironmentMigrationWorkspace({rank,onError=()=>{}}){
 const[data,setData]=useState(null),[busy,setBusy]=useState(true),[msg,setMsg]=useState('')
 const invoke=async body=>{const{data:r,error}=await supabase.functions.invoke('platform-environment-control',{body});if(error)throw error;if(r?.error)throw new Error(r.error);return r}
 const load=async()=>{setBusy(true);try{setData(await invoke({action:'read'}))}catch(e){onError(e.message||String(e))}finally{setBusy(false)}}
 useEffect(()=>{load()},[])
 if(rank<6)return null
 if(busy&&!data)return <section className="env-panel">Loading environment controls…</section>
 const providers=data?.layer2_providers||[],settings=data?.settings||[],manifest=data?.migration_manifest||[],runtime=data?.runtime||{}
 const parsebot=providers.find(x=>x.provider_key==='parsebot'),firecrawl=providers.find(x=>x.provider_key==='firecrawl'),zenrows=providers.find(x=>x.provider_key==='zenrows'),otherProviders=providers.filter(x=>['scrape-do','scraperapi'].includes(x.provider_key))
 const refresh=async text=>{setMsg(text);await load()}
 return <div className="env-stack">
  <section className="env-panel"><div className="env-head"><div><small>Administration / Environment & Migration</small><h2>Integration credentials & production portability</h2><p>Secret values are write-only. Production-specific Supabase keys remain target-generated and are never copied from Pilot.</p></div><button onClick={load}><RefreshCw size={15}/>Refresh</button></div>
   {msg&&<div className="env-ok"><CheckCircle2 size={15}/>{msg}</div>}
   <div className="env-summary">
    <Summary label="Evidence rows" value={fmt(runtime.evidence_rows)}/>
    <Summary label="Storage objects" value={fmt(runtime.storage_objects)}/>
    <Summary label="Cron jobs" value={fmt(runtime.cron_jobs)}/>
    <Summary label="Vault secrets" value={fmt(runtime.vault_secret_count)}/>
    <Summary label="Absolute Evidence paths" value={fmt(runtime.evidence_absolute_storage_paths)} good={Number(runtime.evidence_absolute_storage_paths||0)===0}/>
   </div>
  </section>

  <section className="env-panel"><h3>Acquisition providers</h3><p className="env-help">Configure keys, quotas and endpoints here. Parse.bot remains disabled until its trial endpoint/key is supplied and bounded UAT passes.</p>
   <div className="env-grid">
    {parsebot&&<ProviderCard provider={parsebot} title="Parse.bot" hint="Trial adapter — configure endpoint/key, then enable only after bounded UAT." onSaved={refresh}/>}
    {firecrawl&&<ProviderCard provider={firecrawl} title="Firecrawl" hint="Credential and endpoint status only. Monthly entitlement and reserve are managed in Administration → Scraper Config." onSaved={refresh}/>}
    {zenrows&&<ProviderCard provider={zenrows} title="ZenRows" hint="Terminal governed fallback." onSaved={refresh}/>}
    {otherProviders.map(p=><ProviderCard key={p.id} provider={p} title={p.display_name} hint="Additional governed Layer 2 acquisition provider." onSaved={refresh}/>)}
   </div>
  </section>

  <IntegrationSecrets data={data} onSaved={refresh}/>
  <ConsumerCredentials data={data} onSaved={refresh}/>

  <section className="env-panel"><h3>Production environment</h3><p className="env-help">These are non-secret target values used for cutover planning. Project-generated keys are shown as checklist items only.</p>
   <div className="env-settings">{settings.filter(x=>x.environment_scope!=='current').map(s=><SettingRow key={s.setting_key} setting={s} onSaved={refresh}/>)}</div>
  </section>

  <section className="env-panel"><h3>Supabase Production migration manifest</h3><div className="env-warn"><ShieldCheck size={16}/><span>Database clone/restore alone is not enough: Storage objects, Edge Functions, Auth/API keys and project settings require explicit target work.</span></div>
   <div className="env-manifest">{manifest.map(m=><ManifestRow key={m.component_key} item={m} onSaved={refresh}/>)}</div>
  </section>
 </div>
}

function Summary({label,value,good=false}){return <div className={'env-summary-card '+(good?'good':'')}><small>{label}</small><strong>{value}</strong></div>}

function ProviderCard({provider:p,title,hint,quota=false,onSaved}){
 const[secret,setSecret]=useState(''),[baseUrl,setBaseUrl]=useState(p.base_url||''),[enabled,setEnabled]=useState(Boolean(p.enabled)),[rate,setRate]=useState(p.rate_limit_per_minute??''),[limit,setLimit]=useState(p.billing_config?.monthly_vendor_units_limit??''),[reserve,setReserve]=useState(p.billing_config?.stop_at_vendor_units_remaining??''),[busy,setBusy]=useState(false),[err,setErr]=useState('')
 const control=async(action,payload)=>{const{data,error}=await supabase.functions.invoke('layer2-provider-control',{body:{action,payload}});if(error)throw error;if(data?.error)throw new Error(data.error);return data}
 const saveConfig=async()=>{setBusy(true);setErr('');try{const billing={...(p.billing_config||{})};if(quota){billing.monthly_vendor_units_limit=limit===''?null:Number(limit);billing.stop_at_vendor_units_remaining=reserve===''?null:Number(reserve)}await control('update_provider',{id:p.id,display_name:p.display_name,base_url:baseUrl,auth_scheme:p.auth_scheme,auth_field_name:p.auth_field_name,capabilities:p.capabilities||{},request_template:p.request_template||{},billing_config:billing,enabled,priority:p.priority,rate_limit_per_minute:rate===''?null:Number(rate),concurrency:p.concurrency,timeout_seconds:p.timeout_seconds,operational_owner:p.operational_owner});await onSaved(title+' settings saved.')}catch(e){setErr(e.message)}finally{setBusy(false)}}
 const saveSecret=async()=>{setBusy(true);setErr('');try{await control('set_secret',{id:p.id,secret});setSecret('');await onSaved(title+' credential stored in Vault.')}catch(e){setErr(e.message)}finally{setBusy(false)}}
 return <article className="env-card"><div className="env-card-title"><div><strong>{title}</strong><span>{p.credential_configured?'Credential configured':p.auth_scheme==='none'?'No credential required':'Credential missing'}</span></div><b className={p.enabled?'on':'off'}>{p.enabled?'Enabled':'Disabled'}</b></div><p>{hint}</p>
  <label>Base URL<input value={baseUrl} onChange={e=>setBaseUrl(e.target.value)} placeholder="Provider API endpoint"/></label>
  <div className="env-two"><label>Rate / min<input type="number" min="1" value={rate} onChange={e=>setRate(e.target.value)}/></label><label className="env-check"><input type="checkbox" checked={enabled} onChange={e=>setEnabled(e.target.checked)}/>Enabled</label></div>
  {quota&&<div className="env-two"><label>Monthly vendor units<input type="number" min="1" value={limit} onChange={e=>setLimit(e.target.value)}/></label><label>Stop at remaining<input type="number" min="0" value={reserve} onChange={e=>setReserve(e.target.value)}/></label></div>}
  <button disabled={busy} onClick={saveConfig}>Save provider settings</button>
  {p.auth_scheme!=='none'&&<><label>Set / rotate API key<input type="password" autoComplete="new-password" value={secret} onChange={e=>setSecret(e.target.value)} placeholder="Write-only; never displayed"/></label><button disabled={busy||!secret} onClick={saveSecret}><KeyRound size={13}/>Save credential</button></>}
  {err&&<div className="env-error">{err}</div>}
 </article>
}

function IntegrationSecrets({data,onSaved}){
 const integrations=data?.integration_secrets||[],profiles=data?.layer3_profiles||[]
 const[apollo,setApollo]=useState(''),[automation,setAutomation]=useState(''),[profileId,setProfileId]=useState(profiles[0]?.id||''),[openrouter,setOpenrouter]=useState(''),[reason,setReason]=useState('Production credential rotation'),[busy,setBusy]=useState(false),[err,setErr]=useState('')
 useEffect(()=>{if(!profileId&&profiles[0]?.id)setProfileId(profiles[0].id)},[profiles.length])
 const env=async(action,payload)=>{const{data:r,error}=await supabase.functions.invoke('platform-environment-control',{body:{action,payload}});if(error)throw error;if(r?.error)throw new Error(r.error);return r}
 const setIntegration=async(key,secret,clear)=>{setBusy(true);setErr('');try{await env('set_integration_secret',{integration_key:key,secret});clear();await onSaved(human(key)+' credential stored securely.')}catch(e){setErr(e.message)}finally{setBusy(false)}}
 const saveOpenRouter=async()=>{setBusy(true);setErr('');try{const{data:r,error}=await supabase.functions.invoke('layer3-provider-control',{body:{action:'set_credential',profile_id:profileId,credential:openrouter,reason}});if(error)throw error;if(r?.error)throw new Error(r.error);setOpenrouter('');await onSaved('OpenRouter credential stored in Vault.')}catch(e){setErr(e.message)}finally{setBusy(false)}}
 const apolloState=integrations.find(x=>x.integration_key==='apollo')
 return <section className="env-panel"><h3>Other integration credentials</h3><div className="env-grid">
  <article className="env-card"><strong>Apollo contact enrichment</strong><span>{apolloState?.configured?'Credential configured':'Vault credential not configured'}</span><label>API key<input type="password" value={apollo} onChange={e=>setApollo(e.target.value)} placeholder="Write-only"/></label><button disabled={busy||!apollo} onClick={()=>setIntegration('apollo',apollo,()=>setApollo(''))}>Save Apollo key</button><small>Worker now prefers the Admin-managed Vault key; legacy Edge env key remains fallback during transition.</small></article>
  <article className="env-card"><strong>OpenRouter / Layer 3</strong><label>Profile<select value={profileId} onChange={e=>setProfileId(e.target.value)}>{profiles.map(p=><option key={p.id} value={p.id}>{p.code} · {p.model_identifier}</option>)}</select></label><label>API key<input type="password" value={openrouter} onChange={e=>setOpenrouter(e.target.value)} placeholder="Write-only"/></label><label>Reason<input value={reason} onChange={e=>setReason(e.target.value)}/></label><button disabled={busy||!profileId||openrouter.length<20} onClick={saveOpenRouter}>Save OpenRouter key</button></article>
  <article className="env-card"><strong>Production automation</strong><p>Create a new Production-only automation key. Do not reuse the Pilot automation credential.</p><label>New key<input type="password" value={automation} onChange={e=>setAutomation(e.target.value)} placeholder="Production only"/></label><button disabled={busy||automation.length<20} onClick={()=>setIntegration('production_automation',automation,()=>setAutomation(''))}>Store Production automation key</button></article>
 </div>{err&&<div className="env-error">{err}</div>}</section>
}


function ConsumerCredentials({data,onSaved}){
 const rows=data?.consumer_credentials||[]
 const[values,setValues]=useState({zoho_api:'',website_api:''}),[busy,setBusy]=useState(false),[err,setErr]=useState('')
 const save=async key=>{const token=values[key]||'';if(token.length<24)return;setBusy(true);setErr('');try{const row=rows.find(x=>x.integration_key===key);const credentialName=row?.credential_name||`${key.replace('_api','')}-current`;const{data:r,error}=await supabase.functions.invoke('platform-environment-control',{body:{action:'set_consumer_token',payload:{integration_key:key,credential_name:credentialName,token}}});if(error)throw error;if(r?.error)throw new Error(r.error);setValues(v=>({...v,[key]:''}));await onSaved(human(key)+' token rotated for the current environment.')}catch(e){setErr(e.message)}finally{setBusy(false)}}
 return <section className="env-panel"><h3>Current-environment consumer API tokens</h3><div className="env-warn"><AlertTriangle size={16}/><span>These token hashes authenticate the environment you are currently logged into. Do not enter Production tokens while using Pilot. After the Production project is created, rotate them from this same page in Production.</span></div><div className="env-grid">{rows.map(row=><article className="env-card" key={row.integration_key}><strong>{row.display_name}</strong><span>{row.configured?'Configured':'Not configured'} · {human(row.storage_mode)}</span><small>Raw token is never stored or returned. Production requires rotation because the existing hash cannot recover the Pilot token.</small><label>Set / rotate current-environment token<input type="password" autoComplete="new-password" value={values[row.integration_key]||''} onChange={e=>setValues(v=>({...v,[row.integration_key]:e.target.value}))} placeholder="Write-only bearer token"/></label><button disabled={busy||(values[row.integration_key]||'').length<24} onClick={()=>save(row.integration_key)}>Rotate token</button></article>)}</div>{err&&<div className="env-error">{err}</div>}</section>
}

function SettingRow({setting:s,onSaved}){
 const editable=s.management_mode==='admin_edit';const raw=s.setting_value==null?'':typeof s.setting_value==='string'?s.setting_value:JSON.stringify(s.setting_value);const[value,setValue]=useState(raw),[busy,setBusy]=useState(false)
 useEffect(()=>setValue(raw),[raw])
 const save=async()=>{setBusy(true);try{const{data,error}=await supabase.functions.invoke('platform-environment-control',{body:{action:'set_setting',payload:{setting_key:s.setting_key,value:value||null}}});if(error)throw error;if(data?.error)throw new Error(data.error);await onSaved(s.display_name+' saved.')}finally{setBusy(false)}}
 return <div className="env-setting"><div><strong>{s.display_name}</strong><small>{s.description}</small></div>{editable?<div className="env-setting-edit"><input value={value} onChange={e=>setValue(e.target.value)} placeholder="Not configured"/><button disabled={busy} onClick={save}>Save</button></div>:<div><b>{human(s.management_mode)}</b><small>{s.status}</small></div>}</div>
}

function ManifestRow({item:m,onSaved}){
 const[busy,setBusy]=useState(false)
 const setStatus=async status=>{setBusy(true);try{const{data,error}=await supabase.functions.invoke('platform-environment-control',{body:{action:'set_manifest_status',payload:{component_key:m.component_key,target_status:status}}});if(error)throw error;if(data?.error)throw new Error(data.error);await onSaved(m.display_name+' status updated.')}finally{setBusy(false)}}
 return <div className="env-manifest-row"><div><strong>{m.display_name}</strong><small>{m.production_action}</small><em>{m.validation_rule}</em></div><div><span>{human(m.migration_mode)}</span><select disabled={busy} value={m.target_status} onChange={e=>setStatus(e.target.value)}>{['pending','ready','verified','blocked','not_applicable'].map(x=><option key={x} value={x}>{human(x)}</option>)}</select></div></div>
}