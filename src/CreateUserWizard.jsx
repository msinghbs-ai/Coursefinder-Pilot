// Users & roles › Create user (v2.16.35, Platform Admin 18 Nov 2026 10:31 and 10:33): a guided flow in four steps (Person, Role, Sign-in, Review),
// then a confirmation that says exactly what happened and what the person receives. The role step shows what the chosen role can and cannot do,
// from the role guides (src/guide/roleGuides.js); each field is checked as it is typed. The server (edge function admin-user-management, action
// create) checks the same again and is the only place the account is made; a password is sent to it once and never stored or shown again.
import React,{useMemo,useState}from'react'
import{AlertTriangle,ArrowLeft,ArrowRight,Check,Eye,EyeOff,KeyRound,Mail,UserPlus,X}from'lucide-react'
import{ROLE_GUIDES}from'./guide/roleGuides'
import{fmtDateTime}from'./lib/format.js'

export const STEPS=[['person','Person'],['role','Role'],['signin','Sign-in'],['review','Review']]
export const emailProblem=(email,existing=[])=>{const e=String(email||'').trim().toLowerCase()
  if(!e)return'Enter the person\'s email address.'
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e))return'This is not a complete email address (name@organisation.domain).'
  if(existing.map(x=>String(x||'').toLowerCase()).includes(e))return'A user with this email already exists. Use Roles or Resend invite on their row.'
  return''}
// the server needs 12 characters; the screen also asks for a letter and a digit so a UAT password is not trivially guessed
export const passwordChecks=p=>[['At least 12 characters',String(p||'').length>=12],['A letter',/[A-Za-z]/.test(p||'')],['A number',/\d/.test(p||'')]]
const guideFor=role=>ROLE_GUIDES.find(g=>g.rank===Number(role?.rank))

export default function CreateUserWizard({roles=[],existing=[],onClose,onSubmit,onDone}){
  const sorted=useMemo(()=>[...roles].sort((a,b)=>a.rank-b.rank),[roles])
  const[step,setStep]=useState(0),[email,setEmail]=useState(''),[fullName,setFullName]=useState(''),[role,setRole]=useState('viewer'),[extra,setExtra]=useState([]),[multi,setMulti]=useState(false)
  const[expiry,setExpiry]=useState(''),[mode,setMode]=useState('invite'),[password,setPassword]=useState(''),[show,setShow]=useState(false),[touched,setTouched]=useState({}),[busy,setBusy]=useState(false),[err,setErr]=useState(''),[done,setDone]=useState(null)
  const chosen=sorted.find(r=>r.code===role)||sorted[0],g=guideFor(chosen),all=[...new Set([role,...(multi?extra:[])])],platform=all.includes('platform_admin')
  const eBad=emailProblem(email,existing),pChecks=passwordChecks(password),pBad=mode==='password'&&pChecks.some(([,ok])=>!ok)
  const stepBad=[eBad,!role?'Choose a role.':'',pBad?'The password does not meet every rule below.':'',''][step]
  const next=()=>{setTouched(t=>({...t,[STEPS[step][0]]:true}));if(!stepBad)setStep(s=>Math.min(s+1,3))}
  async function create(){setErr('');setBusy(true)
    try{const expiresAt=expiry&&!platform?new Date(expiry).toISOString():null
      await onSubmit({email:email.trim(),mode,password:mode==='password'?password:'',roles:all,expiresAt,fullName:fullName.trim()})
      setPassword('');setDone({email:email.trim(),mode,roles:all.map(c=>sorted.find(r=>r.code===c)?.name||c),name:fullName.trim()})}
    catch(e){setErr(String(e?.message||e).replace(/^Error:\s*/,'').replace(/_/g,' '))}finally{setBusy(false)}}
  if(done)return <div className="ar-modal-backdrop" role="presentation"><div className="ar-modal cuw" role="dialog" aria-modal="true" aria-labelledby="cuw-done" data-cuw-done={done.mode}>
    <header><div><h2 id="cuw-done"><Check size={18}/> {done.mode==='invite'?'Invitation sent':'User created'}</h2><p>{done.email} · {done.roles.join(', ')}</p></div><button type="button" className="ar-icon" aria-label="Close" onClick={()=>onDone?.()}><X size={18}/></button></header>
    {done.mode==='invite'?<ul className="cuw-next"><li><Mail size={15}/><span>{done.name||done.email} receives an email with a link that opens the StudySearch Admin sign-in, where they choose their own password.</span></li>
      <li><UserPlus size={15}/><span>Their row shows <strong>Invited</strong> until they accept. If the email does not arrive or the link has expired, use <strong>Resend invite</strong> on their row.</span></li></ul>
      :<ul className="cuw-next"><li><KeyRound size={15}/><span>The account can sign in now with the password you set. It is not stored or shown anywhere in StudySearch: share it with the person by a secure route.</span></li></ul>}
    <p className="ar-help">The change is recorded under Recent access changes.</p>
    <footer><button type="button" className="ar-secondary" onClick={()=>{setDone(null);setStep(0);setEmail('');setFullName('');setTouched({})}} data-cuw-another>Create another</button><button type="button" className="ar-primary" onClick={()=>onDone?.()} data-cuw-finish>Done</button></footer>
  </div></div>
  return <div className="ar-modal-backdrop" role="presentation"><form className="ar-modal cuw" role="dialog" aria-modal="true" aria-labelledby="cuw-title" onSubmit={e=>{e.preventDefault();step<3?next():create()}} data-cuw-step={STEPS[step][0]}>
    <header><div><h2 id="cuw-title">Create user</h2><p>Four short steps. Nothing is created until you choose Create on the last one.</p></div><button type="button" className="ar-icon" aria-label="Close" onClick={onClose}><X size={18}/></button></header>
    <ol className="cuw-steps" aria-label="Steps">{STEPS.map(([k,l],i)=><li key={k} className={i===step?'is-on':i<step?'is-done':''} aria-current={i===step?'step':undefined}><span>{i<step?<Check size={12}/>:i+1}</span>{l}</li>)}</ol>
    {err&&<div className="ar-alert error compact" role="alert"><AlertTriangle size={15}/><span>{err}</span></div>}
    {step===0&&<div className="cuw-body">
      <label>Email<input type="email" autoFocus value={email} onChange={e=>setEmail(e.target.value)} onBlur={()=>setTouched(t=>({...t,email:true}))} aria-invalid={Boolean((touched.email||touched.person)&&eBad)} aria-describedby="cuw-email-msg" placeholder="name@organisation.edu.au" data-cuw-email/>
        <small id="cuw-email-msg" className={(touched.email||touched.person)&&eBad?'cuw-bad':''}>{(touched.email||touched.person)&&eBad?eBad:'The address they sign in with. It cannot be changed later from here.'}</small></label>
      <label>Full name<input value={fullName} onChange={e=>setFullName(e.target.value)} maxLength="120" autoComplete="off" placeholder="As it should appear in the invitation email" data-cuw-name/><small>Optional. The invitation greets them by this name.</small></label>
    </div>}
    {step===1&&<div className="cuw-body cuw-role">
      <fieldset><legend>Choose one role</legend><div className="cuw-roles">{sorted.map(r=><label key={r.code} className={role===r.code?'selected':''}><input type="radio" name="cuw-role" checked={role===r.code} onChange={()=>setRole(r.code)} data-cuw-role={r.code}/><span className={`ar-role-rank rank-${r.rank}`}>{r.rank}</span><span><strong>{r.name}</strong><small>{guideFor(r)?.purpose||r.description}</small></span></label>)}</div></fieldset>
      {g&&<aside className="cuw-perms" data-cuw-perms={g.id} aria-live="polite"><h3>{g.role}: what they can and cannot do</h3>
        <div className="cuw-two"><div><h4>Can</h4><ul>{g.can.map(x=><li key={x}><Check size={13}/>{x}</li>)}</ul></div><div><h4>Cannot</h4><ul>{g.cannot.map(x=><li key={x}><X size={13}/>{x}</li>)}</ul></div></div>
        <p className="ar-help">The full guide is under Guides › Role guides.</p></aside>}
      <label>Role expiry<input type="datetime-local" value={expiry} disabled={platform} onChange={e=>setExpiry(e.target.value)} data-cuw-expiry/><small>{platform?'A Platform Admin role cannot expire.':'Optional. After this date and time the role ends and the person keeps no access.'}</small></label>
      <details className="cuw-multi" open={multi} onToggle={e=>setMulti(e.currentTarget.open)}><summary>Add a second role (for testing only)</summary>
        <p className="ar-help">The highest active role applies. Use one role per person unless you are testing additive access.</p>
        <div className="cuw-extra">{sorted.filter(r=>r.code!==role).map(r=><label key={r.code}><input type="checkbox" checked={extra.includes(r.code)} onChange={()=>setExtra(x=>x.includes(r.code)?x.filter(c=>c!==r.code):[...x,r.code])}/>{r.name}</label>)}</div></details>
    </div>}
    {step===2&&<div className="cuw-body">
      <div className="ar-mode-grid"><label className={mode==='invite'?'selected':''}><input type="radio" name="cuw-mode" checked={mode==='invite'} onChange={()=>setMode('invite')} data-cuw-mode="invite"/><Mail size={17}/><span><strong>Send invitation (recommended)</strong><small>They get an email with a link to the Admin sign-in and choose their own password. You never see it.</small></span></label>
        <label className={mode==='password'?'selected':''}><input type="radio" name="cuw-mode" checked={mode==='password'} onChange={()=>setMode('password')} data-cuw-mode="password"/><KeyRound size={17}/><span><strong>Set a password</strong><small>For controlled UAT and test accounts only. You give the password to the person yourself.</small></span></label></div>
      {mode==='invite'&&<p className="ar-help" data-cuw-invite-help>The invitation link works once. If it expires before they use it, choose Resend invite on their row; the earlier link stops working.</p>}
      {mode==='password'&&<label>Password<span className="cuw-pw"><input type={show?'text':'password'} autoComplete="new-password" value={password} onChange={e=>setPassword(e.target.value)} aria-describedby="cuw-pw-rules" data-cuw-password/>
        <button type="button" className="ar-icon" aria-label={show?'Hide password':'Show password'} onClick={()=>setShow(x=>!x)}>{show?<EyeOff size={16}/>:<Eye size={16}/>}</button></span>
        <ul id="cuw-pw-rules" className="cuw-rules">{pChecks.map(([l,ok])=><li key={l} className={ok?'ok':''}>{ok?<Check size={12}/>:<X size={12}/>}{l}</li>)}</ul>
        <small>Sent once to the protected edge function. It is never stored in the access history and cannot be shown again.</small></label>}
    </div>}
    {step===3&&<div className="cuw-body" data-cuw-review><table className="cuw-sum"><tbody>
      <tr><th>Email</th><td>{email.trim()}</td></tr><tr><th>Name</th><td>{fullName.trim()||'Not given'}</td></tr>
      <tr><th>Role</th><td>{all.map(c=>sorted.find(r=>r.code===c)?.name||c).join(', ')}</td></tr>
      <tr><th>Expiry</th><td>{platform||!expiry?'None':fmtDateTime(new Date(expiry))}</td></tr>
      <tr><th>Sign-in</th><td>{mode==='invite'?'Invitation email to the address above':'Password you set (share it securely)'}</td></tr></tbody></table>
      <p className="ar-help">Choose Create to make the account. It is recorded under Recent access changes.</p></div>}
    {touched[STEPS[step][0]]&&stepBad&&step!==0&&<p className="cuw-bad" role="alert">{stepBad}</p>}
    <footer><button type="button" className="ar-secondary" onClick={()=>step?setStep(s=>s-1):onClose?.()} data-cuw-back>{step?<><ArrowLeft size={14}/>Back</>:'Cancel'}</button>
      {step<3?<button type="submit" className="ar-primary" data-cuw-next>Next<ArrowRight size={14}/></button>:<button type="submit" className="ar-primary" disabled={busy} data-cuw-create>{busy?'Creating…':mode==='invite'?'Create and send invitation':'Create user'}</button>}</footer>
  </form></div>
}
