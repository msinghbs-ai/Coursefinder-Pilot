// CF-247 (Platform Admin 17 Nov 2026 14:40, S1-RM-Design): Users & roles › Links & Email Templates. The Admin site URL, the Admin guide link and the
// Invite user and Reset password emails, edited here by a Platform Admin (rank 6) and saved with a reason.
// Reads: public.admin_auth_template_settings_read. Saves: public.admin_auth_template_settings_save(payload, reason), which writes the control log.
// v2.16.35 (Platform Admin 18 Nov 2026 10:31 and 10:33): the body is edited as formatted text (src/RichEmailEditor.jsx: toolbar, Insert link,
// a Sign in button and plain-English variable chips; Edit HTML shows the code). The route the mail takes now (Supabase Built-in or Resend API), the
// sender and the key are stated at the top of the tab, and each button names what it does: Save Provider Settings and Send Test Email on the delivery
// card, Save Template and Send This Template as a Test on the template card.
// Save Template then asks admin-user-management to copy what is saved to Supabase Auth; that copy happens only when a management token is set as an
// Edge Function secret, and the screen says which of the two happened. The preview is drawn in a sandboxed frame (no scripts) with sample values.
import React,{useCallback,useEffect,useMemo,useRef,useState}from'react'
import{RefreshCw}from'lucide-react'
import{Button,StatusChip,EmptyInline,fmtDateTime}from'./ui-kit'
import{supabase}from'./lib/supabase'
import{plainError}from'./lib/errors'
import{accessApi}from'./access-roles-api'
import'./auth-email-templates.css'
import RichEmailEditor from'./RichEmailEditor'

export const TEMPLATE_KINDS=[['invite','Invite User'],['recovery','Reset Password']]
export const TOKENS=['link','guide_link','user_email','user_name','role']
const esc=v=>String(v??'').replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
// what the preview shows in place of each token
export const sampleValues=(siteUrl,guideLink)=>({link:`${String(siteUrl||'').replace(/\/+$/,'')}/#sample-sign-in-link`,guide_link:guideLink,user_email:'alex.nguyen@example.com',user_name:'Alex Nguyen',role:'Curator'})
export const renderTemplate=(text,values)=>String(text||'').replace(/\{\{\s*(link|guide_link|user_email|user_name|role)\s*\}\}/g,(_m,t)=>esc(values[t]))
// what Supabase Auth wants in place of each token (the same translation admin-user-management makes when it copies a save to Auth)
const AUTH_TOKENS={link:'{{ .ConfirmationURL }}',user_email:'{{ .Email }}',user_name:'{{ .Data.full_name }}',role:'{{ .Data.role }}'}
export const toAuthTemplate=(text,guideLink)=>String(text||'').replace(/(,?[ ]?)\{\{\s*user_name\s*\}\}/g,(_m,lead)=>`{{ if .Data.full_name }}${lead}{{ .Data.full_name }}{{ end }}`).replace(/\{\{\s*(link|guide_link|user_email|role)\s*\}\}/g,(_m,t)=>t==='guide_link'?esc(guideLink):AUTH_TOKENS[t])
export const unknownTokens=text=>[...new Set([...String(text||'').matchAll(/\{\{\s*([^{}]*?)\s*\}\}/g)].map(m=>m[1]).filter(t=>!TOKENS.includes(t)))]

export default function AuthEmailTemplates({rank=0,onError,client=null,access=accessApi}){
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const[d,setD]=useState(null),[err,setErr]=useState(''),[note,setNote]=useState(''),[busy,setBusy]=useState(''),[status,setStatus]=useState(null)
  const[form,setForm]=useState(null),[dv,setDv]=useState(null),[dform,setDform]=useState(null),[newKey,setNewKey]=useState(''),[kind,setKind]=useState('invite'),[reason,setReason]=useState(''),[testTo,setTestTo]=useState(''),[dReason,setDReason]=useState(''),[dNote,setDNote]=useState(null)
  const subjectRef=useRef(null),bodyRef=useRef(null),last=useRef('body'),[codeView,setCodeView]=useState(false),[resetN,setResetN]=useState(0)
  const load=useCallback(()=>{setErr('')
    Promise.resolve(rpc('admin_auth_template_settings_read',{})).then(({data,error})=>{if(error){setErr(plainError(error));return}
      setD(data);setForm({site_url:data.settings.site_url,guide_link:data.settings.guide_link,templates:JSON.parse(JSON.stringify(data.settings.templates))})}).catch(e=>setErr(plainError(e)))
    // v2.16.23: who sends the emails (Supabase built-in or Resend), the sender name and from address. The Resend key is write-only: it is never read back.
    Promise.resolve(rpc('admin_email_delivery_read',{})).then(({data,error})=>{if(error)return;setDv(data.delivery);setDform({email_provider:data.delivery.email_provider,sender_name:data.delivery.sender_name,from_email:data.delivery.from_email});setNewKey('')}).catch(()=>{})
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
  const dDirty=Boolean(dv&&dform)&&(dform.email_provider!==dv.email_provider||dform.sender_name.trim()!==dv.sender_name||dform.from_email.trim().toLowerCase()!==dv.from_email||newKey.trim()!=='')
  const viaResend=status?.delivery?.effective==='resend'
  // the latest test email in the control log (sent through Resend or Supabase): proves the key and the sender's domain
  const lastTest=useMemo(()=>{const e=(d?.last_events||[]).find(x=>x.action==='auth_template_test');return e?{at:e.at,ok:e.synced===true}:null},[d?.last_events])
  const dBad=Boolean(dform)&&dform.email_provider==='resend'&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(dform.from_email.trim())
  const bad=[...unknownTokens(t.subject),...unknownTokens(t.body)]
  const missingLink=!/\{\{\s*link\s*\}\}/.test(t.body)
  // a token chip writes its token where the cursor last was, in the subject or the body
  function insert(token){const field=last.current,el=field==='subject'?subjectRef.current:bodyRef.current,text=`{{${token}}}`,cur=t[field]||''
    const a=el?.selectionStart??cur.length,b=el?.selectionEnd??cur.length
    setT(field,cur.slice(0,a)+text+cur.slice(b))
    requestAnimationFrame(()=>{if(el){el.focus();el.setSelectionRange(a+text.length,a+text.length)}})}
  function resetDefault(){setForm(f=>({...f,templates:{...f.templates,[kind]:{...d.defaults.templates[kind]}}}));setResetN(n=>n+1);setNote(`The ${kind==='invite'?'Invite User':'Reset Password'} template is back to the default here. It is not saved until Save Template.`)}
  async function save(){const why=reason.trim();if(why.length<4){setNote('Give a reason for the change (it is kept in the control log).');return}
    setBusy('save');setNote('')
    try{const said=[]
      if(dirty){const{data,error}=await rpc('admin_auth_template_settings_save',{p_payload:form,p_reason:why});if(error)throw error
        said.push(`Templates saved${data?.changed?.length?` (${data.changed.join(', ')})`:''}.`)}
      let sync=null;if(dirty){try{sync=await access.templatesSync()}catch(e){sync={synced:false,note:plainError(e)}}}
      const st=await Promise.resolve(access.templatesStatus()).catch(()=>null)
      if(st?.delivery?.effective==='resend')said.push(`Invitations and resets sent from the Admin go through Resend as ${st.delivery.sender_name}, using the templates saved here.`)
      else if(dirty&&!sync?.synced)said.push('Supabase Auth still sends the previous emails until the admin workflow supabase-auth-config.yml is run, or the copied HTML is pasted in the dashboard.')
      setReason('');setNote(said.join(' '));load()}
    catch(e){const m=plainError(e);setNote(m);onError?.(m)}finally{setBusy('')}}
  // v2.16.21: the instant fallback while no management token is set. Copies the selected template as Supabase Auth reads it, to paste in the dashboard.
  async function copyForDashboard(what){const text=toAuthTemplate(what==='subject'?t.subject:t.body,form.guide_link)
    try{await navigator.clipboard.writeText(text);setNote(`${kind==='invite'?'Invite User':'Reset Password'} ${what==='subject'?'subject':'HTML'} copied. Paste it in the Supabase dashboard: Authentication › Emails › ${kind==='invite'?'Invite user':'Reset password'}.`)}
    catch{setNote('The browser did not allow copying. Select the text in the Body box and copy it by hand; replace {{link}} with {{ .ConfirmationURL }}.')}}
  // v2.16.27 (Platform Admin 17 Nov 2026 22:31): the Email delivery provider card saves itself, with its own reason, and tests itself.
  // The button is always there and never greyed for a missing field: it says in the card what is missing instead.
  async function saveDelivery(){const why=dReason.trim()
    if(dBad){setDNote({ok:false,text:'Not saved. Resend needs a From Email on a domain verified in Resend.'});return}
    if(why.length<4){setDNote({ok:false,text:'Not saved. Give a reason for the change in the Reason box (it is kept in the control log).'});return}
    if(!dDirty){setDNote({ok:false,text:'Nothing to save: the provider, sender name and from email are as saved, and no new key was typed.'});return}
    setBusy('dsave');setDNote(null)
    try{const said=[]
      // the key travels only when a new one was typed; an empty field keeps the stored key
      const payload={...dform,...(newKey.trim()?{resend_api_key:newKey.trim()}:{})};const{data,error}=await rpc('admin_email_delivery_save',{p_payload:payload,p_reason:why});if(error)throw error
      setNewKey('');said.push(`Email provider settings saved${data?.changed?.length?` (${data.changed.map(c=>c==='resend_api_key'?'Resend API key':c.replace(/_/g,' ')).join(', ')})`:''}.`)
      const st=await Promise.resolve(access.templatesStatus()).catch(()=>null)
      if(st?.delivery?.effective==='resend')said.push(`Invitations and resets sent from the Admin now go through Resend as ${st.delivery.sender_name} <${st.delivery.from_email}>.`)
      else if(dform.email_provider==='resend')said.push('Resend is chosen but not in use yet: it needs a saved API key and a from email. Supabase built-in still sends.')
      else said.push('Supabase built-in sends the emails.')
      setDReason('');setDNote({ok:true,text:said.join(' ')});load()}
    catch(e){const m=plainError(e);setDNote({ok:false,text:`Not saved. ${m}`});onError?.(m)}finally{setBusy('')}}
  async function sendDeliveryTest(){
    if(dDirty){setDNote({ok:false,text:'Save Provider Settings first: the test uses the saved sender name, from email and key, not what is typed here.'});return}
    setBusy('dtest');setDNote(null)
    try{const r=await access.deliveryTest(kind)
      setDNote({ok:true,text:`Resend accepted the test ${kind==='invite'?'Invite User':'Reset Password'} email to ${r?.sent_to}, from ${r?.from||'the saved sender'}.${r?.resend_id?` Resend reference: ${r.resend_id}.`:''}${r?.in_use?'':' Supabase built-in is still the provider for real invitations and resets until Resend API is chosen and saved.'} The link in a test signs nobody in.`});load()}
    catch(e){setDNote({ok:false,text:`Test not sent. ${plainError(e).replace(/_/g,' ')}`})}finally{setBusy('')}}
  async function sendTest(){setBusy('test');setNote('')
    try{const r=await access.templateTest(kind,testTo.trim());setNote(r?.provider==='resend'?`Test ${kind==='invite'?'Invite User':'Reset Password'} email sent through Resend to ${r?.sent_to}, from the templates saved here. Its link signs nobody in.`:`Reset password email sent to ${r?.sent_to}. It is the email Supabase Auth holds now.`);load()}
    catch(e){const m=plainError(e).replace(/_/g,' ');setNote(m)}finally{setBusy('')}}
  return <div className="aet" data-auth-email-templates>
    <div className="aet-bar"><p className="sl-sub">Where emailed links open, and the wording of the two emails the Admin sends. A save needs a reason and is kept in the control log.</p>
      <Button compact onClick={load} data-aet-refresh><RefreshCw size={13}/> Refresh</Button></div>
    {/* v2.16.35: where the mail goes now, stated once at the top of the tab */}
    <section className={`aet-route${viaResend?' is-resend':''}`} data-aet-route={viaResend?'resend':'supabase'} aria-label="Email delivery route">
      <div><span className="aet-route-label">Mail goes via</span><StatusChip tone={viaResend?'success':'neutral'} label={viaResend?'Resend API':'Supabase Built-in'}/></div>
      <div><span className="aet-route-label">Sender</span><strong data-aet-route-sender>{viaResend?`${status.delivery.sender_name} <${status.delivery.from_email}>`:dv?.from_email?`Supabase Auth (Resend would send as ${dv.from_email})`:'Supabase Auth'}</strong></div>
      <div><span className="aet-route-label">Resend key</span><StatusChip tone={dv?.key_saved?'success':'warning'} label={dv?.key_saved?`Saved (re_••••${dv.key_hint||''})`:'No key saved'}/></div>
      <div><span className="aet-route-label">Sender domain</span><small data-aet-route-verified>{lastTest?`Last test ${lastTest.ok?'accepted':'refused'} ${fmtDateTime(lastTest.at)}`:'Not proved yet: Send Test Email proves the key and the From Email domain'}</small></div>
    </section>
    {note&&<p className="aet-note" role="status" data-aet-note>{note}</p>}
    {viaResend&&<p className="aet-note" role="status" data-aet-via-resend>Invitations and password resets sent from Users &amp; roles go through <strong>Resend</strong> as {status.delivery.sender_name} &lt;{status.delivery.from_email}&gt;, written from the templates saved here. Only <em>Forgot password?</em> on the sign-in screen is still sent by Supabase Auth with the template it holds.</p>}
    {status&&status.management_token_configured===false&&!viaResend&&<div className="aet-banner" role="alert" data-aet-no-token>
      <strong>Saving here does not change the emails Supabase Auth sends.</strong>
      <p>Save Template stores your templates here with the reason. Supabase Auth is updated by the admin workflow <code>supabase-auth-config.yml</code> (Platform Admin decision 17 Nov 2026: no account token is kept in the edge function). Until that workflow is run, invitations and resets go out with the previous template. To change them straight away, copy the selected template and paste it in the Supabase dashboard (Authentication › Emails).</p>
      <div className="aet-actions"><Button compact onClick={()=>copyForDashboard('body')} data-aet-copy-html>Copy HTML for Supabase Dashboard</Button><Button compact onClick={()=>copyForDashboard('subject')} data-aet-copy-subject>Copy subject</Button><span className="sl-sub">Copies the {kind==='invite'?'Invite User':'Reset Password'} template selected below.</span></div>
    </div>}
    <section className="cf-card aet-card" data-aet-links><h3>Link settings</h3>
      <div className="aet-two">
        <label>Admin Site URL<input type="url" value={form.site_url} onChange={e=>setForm(f=>({...f,site_url:e.target.value}))} data-aet-site-url placeholder={d.defaults.site_url}/>
          <small>The address of this Admin. Saved to Supabase Auth as its site URL when synced.</small></label>
        <label>Admin Guide Link <code>{'{{guide_link}}'}</code><input type="url" value={form.guide_link} onChange={e=>setForm(f=>({...f,guide_link:e.target.value}))} data-aet-guide-link placeholder={d.defaults.guide_link}/>
          <small>Written into the emails wherever <code>{'{{guide_link}}'}</code> appears.</small></label>
      </div>
      <p className="sl-sub" data-aet-status>Links in the emails return to <strong>{status?.login_url||'the Admin sign-in'}</strong> (the edge function&rsquo;s own setting, which must also be listed under Redirect URLs in Supabase Auth). Supabase Auth is updated: <StatusChip tone={status?.management_token_configured?'success':'neutral'} label={status?.management_token_configured?'on save':'by the admin workflow, not from this screen'}/></p>
    </section>
    {dform&&<section className="cf-card aet-card" data-aet-delivery><h3>Email delivery provider</h3>
      <div className="pg-views" role="toolbar" aria-label="Provider">{[['supabase','Supabase Built-in'],['resend','Resend API']].map(([k,l])=><button key={k} type="button" className={`pg-view${dform.email_provider===k?' is-on':''}`} aria-pressed={dform.email_provider===k} data-aet-provider={k} onClick={()=>setDform(f=>({...f,email_provider:k}))}>{l}</button>)}</div>
      <div className="aet-two">
        <label>Sender Name<input value={dform.sender_name} maxLength={80} onChange={e=>setDform(f=>({...f,sender_name:e.target.value}))} data-aet-sender-name placeholder="StudySearch PIM Admin"/>
          <small>Shown as who the email is from when Resend sends it.</small></label>
        <label>From Email<input type="email" value={dform.from_email} onChange={e=>setDform(f=>({...f,from_email:e.target.value}))} data-aet-from-email placeholder="noreply@your-verified-domain"/>
          <small>An address on a domain verified in Resend.</small></label>
        <label>Resend API Key (write-only)<input type="password" autoComplete="new-password" spellCheck={false} value={newKey} onChange={e=>setNewKey(e.target.value)} data-aet-resend-key placeholder={dv?.key_saved?'Leave empty to keep the saved key':'re_…'}/>
          <small>Stored encrypted and never shown again. Type a key only to set or replace it. <StatusChip tone={dv?.key_saved?'success':'warning'} label={dv?.key_saved?`Saved (re_••••${dv.key_hint||''})`:'No key saved'}/></small></label>
      </div>
      {dBad&&<p className="aet-warn" data-aet-from-needed>Resend needs a From Email on a domain verified in Resend.</p>}
      <p className="sl-sub" data-aet-delivery-status>In use now: <StatusChip tone={viaResend?'success':'neutral'} label={viaResend?'Resend':'Supabase built-in (sender shows as Supabase Auth)'}/>{status?.delivery?.configured==='resend'&&!viaResend?' Resend is chosen but needs a saved API key and a from email before it is used.':''}{status?.delivery?.key_source==='edge_secret'?' The key in use is the edge function secret RESEND_API_KEY.':''}</p>
      <div className="aet-actions" data-aet-delivery-actions>
        <label className="aet-inline aet-reason">Reason<input value={dReason} onChange={e=>setDReason(e.target.value)} placeholder="Why this change is made" data-aet-delivery-reason/></label>
        <Button compact variant="primary" disabled={busy!==''} onClick={saveDelivery} data-aet-delivery-save>{busy==='dsave'?'Saving…':'Save Provider Settings'}</Button>
        <Button compact disabled={busy!==''} onClick={sendDeliveryTest} data-aet-delivery-test>{busy==='dtest'?'Sending…':'Send Test Email'}</Button>
      </div>
      {dNote&&<p className={dNote.ok?'aet-note':'aet-warn'} role={dNote.ok?'status':'alert'} data-aet-delivery-result data-ok={dNote.ok?'1':'0'}>{dNote.text}</p>}
      <p className="sl-sub" data-aet-delivery-scope><strong>Save Provider Settings</strong> saves this card only (provider, sender, from email and key), with its reason, to the control log. <strong>Send Test Email</strong> proves the route: it sends the {kind==='invite'?'Invite User':'Reset Password'} template selected below through Resend to your own sign-in address, using the saved settings, and shows Resend&rsquo;s answer here. It works before Resend is switched on, so the key and from email can be proved first.</p>
    </section>}
    <section className="cf-card aet-card" data-aet-templates><h3>Email templates</h3>
      <div className="pg-views" role="toolbar" aria-label="Template">{TEMPLATE_KINDS.map(([k,l])=><button key={k} type="button" className={`pg-view${kind===k?' is-on':''}`} aria-pressed={kind===k} data-aet-kind={k} onClick={()=>setKind(k)}>{l}</button>)}</div>
      <div className="aet-edit">
        <div className="aet-fields">
          <label>Subject<input ref={subjectRef} value={t.subject} maxLength={200} onFocus={()=>{last.current='subject'}} onChange={e=>setT('subject',e.target.value)} data-aet-subject/></label>
          <div className="aet-body-label"><span>Body</span><small>Write and format the email here. Variables such as Their name are filled in for each person; the Sign-in link is the magic link.</small></div>
          <RichEmailEditor value={t.body} resetKey={`${kind}:${resetN}`} onChange={v=>setT('body',v)} onFocus={()=>{last.current='body'}} codeView={codeView} onCodeView={setCodeView}
            onTokenCode={k=>{if(codeView||last.current==='subject'){insert(k);return true}return false}} tokens={TOKENS}/>
          {codeView&&<label>Body (HTML)<textarea ref={bodyRef} value={t.body} rows={20} spellCheck={false} onFocus={()=>{last.current='body'}} onChange={e=>setT('body',e.target.value)} data-aet-body/></label>}
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
        <Button compact disabled={busy!==''||(!viaResend&&kind!=='recovery')} title={!viaResend&&kind!=='recovery'?'Supabase Auth only sends an invitation by creating the account: test it by inviting a new address from Create user':undefined} onClick={sendTest} data-aet-test>{busy==='test'?'Sending…':'Send This Template as a Test'}</Button>
        <label className="aet-inline aet-reason">Reason<input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why this change is made" data-aet-reason/></label>
        <Button compact variant="primary" disabled={busy!==''||!dirty||missingLink||bad.length>0||reason.trim().length<4} onClick={save} data-aet-save>{busy==='save'?'Saving…':'Save Template'}</Button>
      </div>
      <p className="sl-sub" data-aet-template-scope><strong>Save Template</strong> saves the link settings and both templates, with the reason. {viaResend?'Send This Template as a Test sends the selected template through Resend, as saved, to your own address or the one entered. The link in a test signs nobody in.':'Send This Template as a Test sends the Reset Password email as Supabase Auth holds it now, to your own account or to another existing user\u2019s address. An invitation is tested by inviting a new address from Create user.'}</p>
    </section>
    <section className="cf-card aet-card" data-aet-events><h3>Recent changes</h3>
      {(d.last_events||[]).length?<ul className="aet-events">{d.last_events.map((e,i)=><li key={i}><span>{fmtDateTime(e.at)}</span><strong>{e.action==='auth_templates_save'?'Saved':e.action==='auth_templates_sync'?(e.synced?'Copied to Supabase Auth':'Not copied to Supabase Auth'):'Test email'}</strong><span>{e.reason||String(e.note||'').replace(/_/g,' ')}</span></li>)}</ul>
        :<EmptyInline text="Nothing saved yet: the default templates are in force."/>}
    </section>
  </div>
}
