// CF-247 (Platform Admin 17 Nov 2026 14:40, S1-RM-Design): Users & roles › Links & Email Templates. The Admin site URL, the Admin guide link and the
// Invite user and Reset password emails, edited here by a Platform Admin (rank 6) and saved with a reason.
// Reads: public.admin_auth_template_settings_read. Saves: public.admin_auth_template_settings_save(payload, reason), which writes the control log.
// Save & Sync then asks admin-user-management to copy what is saved to Supabase Auth; that copy happens only when a management token is set as an
// Edge Function secret, and the screen says which of the two happened. The preview is drawn in a sandboxed frame (no scripts) with sample values.
import React,{useCallback,useEffect,useMemo,useRef,useState}from'react'
import{RefreshCw}from'lucide-react'
import{Button,StatusChip,EmptyInline,fmtDateTime}from'./ui-kit'
import{supabase}from'./lib/supabase'
import{plainError}from'./lib/errors'
import{accessApi}from'./access-roles-api'
import'./auth-email-templates.css'

export const TEMPLATE_KINDS=[['invite','Invite User'],['recovery','Reset Password']]
export const TOKENS=['link','guide_link','user_email','user_name','role']
const esc=v=>String(v??'').replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
// what the preview shows in place of each token
export const sampleValues=(siteUrl,guideLink)=>({link:`${String(siteUrl||'').replace(/\/+$/,'')}/#sample-sign-in-link`,guide_link:guideLink,user_email:'alex.nguyen@example.com',user_name:'Alex Nguyen',role:'Curator'})
export const renderTemplate=(text,values)=>String(text||'').replace(/\{\{\s*(link|guide_link|user_email|user_name|role)\s*\}\}/g,(_m,t)=>esc(values[t]))
// what Supabase Auth wants in place of each token (the same translation admin-user-management makes when it copies a save to Auth)
const AUTH_TOKENS={link:'{{ .ConfirmationURL }}',user_email:'{{ .Email }}',user_name:'{{ .Data.full_name }}',role:'{{ .Data.role }}'}
export const toAuthTemplate=(text,guideLink)=>String(text||'').replace(/\{\{\s*(link|guide_link|user_email|user_name|role)\s*\}\}/g,(_m,t)=>t==='guide_link'?esc(guideLink):AUTH_TOKENS[t])
export const unknownTokens=text=>[...new Set([...String(text||'').matchAll(/\{\{\s*([^{}]*?)\s*\}\}/g)].map(m=>m[1]).filter(t=>!TOKENS.includes(t)))]

export default function AuthEmailTemplates({rank=0,onError,client=null,access=accessApi}){
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const[d,setD]=useState(null),[err,setErr]=useState(''),[note,setNote]=useState(''),[busy,setBusy]=useState(''),[status,setStatus]=useState(null)
  const[form,setForm]=useState(null),[kind,setKind]=useState('invite'),[reason,setReason]=useState(''),[testTo,setTestTo]=useState('')
  const subjectRef=useRef(null),bodyRef=useRef(null),last=useRef('body')
  const load=useCallback(()=>{setErr('')
    Promise.resolve(rpc('admin_auth_template_settings_read',{})).then(({data,error})=>{if(error){setErr(plainError(error));return}
      setD(data);setForm({site_url:data.settings.site_url,guide_link:data.settings.guide_link,templates:JSON.parse(JSON.stringify(data.settings.templates))})}).catch(e=>setErr(plainError(e)))
    Promise.resolve(access.templatesStatus()).then(setStatus).catch(()=>setStatus(null))},[])
  useEffect(()=>{if(rank>=6)load()},[rank])
  const t=form?.templates?.[kind]
  const values=useMemo(()=>sampleValues(form?.site_url,form?.guide_link),[form?.site_url,form?.guide_link])
  const preview=useMemo(()=>t?`<!doctype html><meta charset="utf-8"><body style="margin:0;padding:16px">${renderTemplate(t.body,values)}</body>`:'',[t?.body,values])
  if(rank<6)return <EmptyInline text="Links & Email Templates opens for the Platform Admin."/>
  if(err&&!form)return <EmptyInline text={err}/>
  if(!form)return <p className="sl-sub">Loading…</p>
  const setT=(field,v)=>setForm(f=>({...f,templates:{...f.templates,[kind]:{...f.templates[kind],[field]:v}}}))
  const dirty=JSON.stringify({site_url:form.site_url,guide_link:form.guide_link,templates:form.templates})!==JSON.stringify({site_url:d.settings.site_url,guide_link:d.settings.guide_link,templates:d.settings.templates})
  const bad=[...unknownTokens(t.subject),...unknownTokens(t.body)]
  const missingLink=!/\{\{\s*link\s*\}\}/.test(t.body)
  // a token chip writes its token where the cursor last was, in the subject or the body
  function insert(token){const field=last.current,el=field==='subject'?subjectRef.current:bodyRef.current,text=`{{${token}}}`,cur=t[field]||''
    const a=el?.selectionStart??cur.length,b=el?.selectionEnd??cur.length
    setT(field,cur.slice(0,a)+text+cur.slice(b))
    requestAnimationFrame(()=>{if(el){el.focus();el.setSelectionRange(a+text.length,a+text.length)}})}
  function resetDefault(){setForm(f=>({...f,templates:{...f.templates,[kind]:{...d.defaults.templates[kind]}}}));setNote(`The ${kind==='invite'?'Invite User':'Reset Password'} template is back to the default here. It is not saved until Save & Sync.`)}
  async function save(){const why=reason.trim();if(why.length<4){setNote('Give a reason for the change (it is kept in the control log).');return}
    setBusy('save');setNote('')
    try{const{data,error}=await rpc('admin_auth_template_settings_save',{p_payload:form,p_reason:why});if(error)throw error
      let sync=null;try{sync=await access.templatesSync()}catch(e){sync={synced:false,note:plainError(e)}}
      setReason('');setNote(`Saved${data?.changed?.length?` (${data.changed.join(', ')})`:' (no change)'}. ${sync?.synced?'Supabase Auth now sends these emails.':sync?.note==='management_token_not_configured'?'Not copied to Supabase Auth: no management token is set for the edge function, so Auth keeps sending its current emails.':`Not copied to Supabase Auth (${sync?.note||'unknown'}).`}`);load()}
    catch(e){const m=plainError(e);setNote(m);onError?.(m)}finally{setBusy('')}}
  // v2.16.21: the instant fallback while no management token is set. Copies the selected template as Supabase Auth reads it, to paste in the dashboard.
  async function copyForDashboard(what){const text=toAuthTemplate(what==='subject'?t.subject:t.body,form.guide_link)
    try{await navigator.clipboard.writeText(text);setNote(`${kind==='invite'?'Invite User':'Reset Password'} ${what==='subject'?'subject':'HTML'} copied. Paste it in the Supabase dashboard: Authentication › Emails › ${kind==='invite'?'Invite user':'Reset password'}.`)}
    catch{setNote('The browser did not allow copying. Select the text in the Body box and copy it by hand; replace {{link}} with {{ .ConfirmationURL }}.')}}
  async function sendTest(){setBusy('test');setNote('')
    try{const r=await access.templateTest(kind,testTo.trim());setNote(`Reset password email sent to ${r?.sent_to}. It is the email Supabase Auth holds now, so save and sync first to test a change.`);load()}
    catch(e){const m=plainError(e).replace(/_/g,' ');setNote(m)}finally{setBusy('')}}
  return <div className="aet" data-auth-email-templates>
    <div className="aet-bar"><p className="sl-sub">Where emailed links open, and the wording of the two emails the Admin sends. A save needs a reason and is kept in the control log.</p>
      <Button compact onClick={load} data-aet-refresh><RefreshCw size={13}/> Refresh</Button></div>
    {note&&<p className="aet-note" role="status" data-aet-note>{note}</p>}
    {status&&status.management_token_configured===false&&<div className="aet-banner" role="alert" data-aet-no-token>
      <strong>Supabase Auth still holds the previous emails.</strong>
      <p>Save &amp; Sync stores your templates here, but they are not sent until the secret <code>SB_MANAGEMENT_TOKEN</code> is set for the edge function. Until then invitations and resets go out with the template last pasted in the Supabase dashboard. To change them now, copy the selected template and paste it in the dashboard (Authentication › Emails).</p>
      <div className="aet-actions"><Button compact onClick={()=>copyForDashboard('body')} data-aet-copy-html>Copy HTML for Supabase Dashboard</Button><Button compact onClick={()=>copyForDashboard('subject')} data-aet-copy-subject>Copy subject</Button><span className="sl-sub">Copies the {kind==='invite'?'Invite User':'Reset Password'} template selected below.</span></div>
    </div>}
    <section className="cf-card aet-card" data-aet-links><h3>Link settings</h3>
      <div className="aet-two">
        <label>Admin Site URL<input type="url" value={form.site_url} onChange={e=>setForm(f=>({...f,site_url:e.target.value}))} data-aet-site-url placeholder={d.defaults.site_url}/>
          <small>The address of this Admin. Saved to Supabase Auth as its site URL when synced.</small></label>
        <label>Admin Guide Link <code>{'{{guide_link}}'}</code><input type="url" value={form.guide_link} onChange={e=>setForm(f=>({...f,guide_link:e.target.value}))} data-aet-guide-link placeholder={d.defaults.guide_link}/>
          <small>Written into the emails wherever <code>{'{{guide_link}}'}</code> appears.</small></label>
      </div>
      <p className="sl-sub" data-aet-status>Links in the emails return to <strong>{status?.login_url||'the Admin sign-in'}</strong> (the edge function&rsquo;s own setting, which must also be listed under Redirect URLs in Supabase Auth). Copy to Supabase Auth on save: <StatusChip tone={status?.management_token_configured?'success':'warning'} label={status?.management_token_configured?'on':'off: no management token set'}/></p>
    </section>
    <section className="cf-card aet-card" data-aet-templates><h3>Email templates</h3>
      <div className="pg-views" role="toolbar" aria-label="Template">{TEMPLATE_KINDS.map(([k,l])=><button key={k} type="button" className={`pg-view${kind===k?' is-on':''}`} aria-pressed={kind===k} data-aet-kind={k} onClick={()=>setKind(k)}>{l}</button>)}</div>
      <div className="aet-chips" role="toolbar" aria-label="Insert a variable"><span className="sl-sub">Insert at the cursor:</span>{TOKENS.map(k=><button key={k} type="button" className="aet-chip" data-aet-token={k} onClick={()=>insert(k)}>{`{{${k}}}`}</button>)}</div>
      <div className="aet-edit">
        <div className="aet-fields">
          <label>Subject<input ref={subjectRef} value={t.subject} maxLength={200} onFocus={()=>{last.current='subject'}} onChange={e=>setT('subject',e.target.value)} data-aet-subject/></label>
          <label>Body (HTML)<textarea ref={bodyRef} value={t.body} rows={20} spellCheck={false} onFocus={()=>{last.current='body'}} onChange={e=>setT('body',e.target.value)} data-aet-body/></label>
          {missingLink&&<p className="aet-warn" data-aet-missing-link>The body needs {'{{link}}'}, or the person cannot sign in from the email. It will not save without it.</p>}
          {bad.length>0&&<p className="aet-warn" data-aet-unknown>Not a variable: {bad.map(b=>`{{${b}}}`).join(', ')}. Use one of the five above.</p>}
        </div>
        <div className="aet-preview"><span className="aet-label">Live preview (sample values)</span>
          <p className="aet-subject" data-aet-preview-subject><strong>Subject:</strong> <span dangerouslySetInnerHTML={{__html:renderTemplate(esc(t.subject),values)}}/></p>
          <iframe title="Email preview" sandbox="" srcDoc={preview} data-aet-preview/>
          <small>Shown for {values.user_name} ({values.user_email}), {values.role}.</small></div>
      </div>
      <div className="aet-actions">
        <Button compact onClick={resetDefault} data-aet-reset>Reset to Default</Button>
        <label className="aet-inline">Test address<input type="email" value={testTo} onChange={e=>setTestTo(e.target.value)} placeholder="your own address" data-aet-test-to/></label>
        <Button compact disabled={busy!==''||kind!=='recovery'} title={kind!=='recovery'?'Supabase Auth only sends an invitation by creating the account: test it by inviting a new address from Create user':undefined} onClick={sendTest} data-aet-test>{busy==='test'?'Sending…':'Send Test Email'}</Button>
        <label className="aet-inline aet-reason">Reason<input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why this change is made" data-aet-reason/></label>
        <Button compact variant="primary" disabled={busy!==''||!dirty||missingLink||bad.length>0||reason.trim().length<4} onClick={save} data-aet-save>{busy==='save'?'Saving…':'Save & Sync'}</Button>
      </div>
      <p className="sl-sub">Send Test Email sends the Reset Password email as Supabase Auth holds it now, to your own account or to another existing user&rsquo;s address. An invitation is tested by inviting a new address from Create user.</p>
    </section>
    <section className="cf-card aet-card" data-aet-events><h3>Recent changes</h3>
      {(d.last_events||[]).length?<ul className="aet-events">{d.last_events.map((e,i)=><li key={i}><span>{fmtDateTime(e.at)}</span><strong>{e.action==='auth_templates_save'?'Saved':e.action==='auth_templates_sync'?(e.synced?'Copied to Supabase Auth':'Not copied to Supabase Auth'):'Test email'}</strong><span>{e.reason||String(e.note||'').replace(/_/g,' ')}</span></li>)}</ul>
        :<EmptyInline text="Nothing saved yet: the default templates are in force."/>}
    </section>
  </div>
}
