import React,{useEffect,useMemo,useState}from'react'
import{createRoot}from'react-dom/client'
import{AlertTriangle,ArrowLeft,Check,Clock3,KeyRound,LockKeyhole,Plus,RefreshCw,Search,ShieldCheck,UserCog,UserPlus,UsersRound,X}from'lucide-react'
import{supabase,api}from'./lib/supabase'
import{accessApi}from'./access-roles-api'
import'./access-roles.css'

const ROUTE='#users-roles'
const NAV_CLASS='access-admin-nav'
const host=document.getElementById('access-roles-root')
const root=host?createRoot(host):null

function isActive(){return location.hash===ROUTE||location.hash.startsWith(`${ROUTE}?`)}
function goAdmin(hash='#administration'){location.hash=hash}

function ensureNav(){document.querySelectorAll(`.${NAV_CLASS}`).forEach(el=>el.remove())}

function AccessBootstrap(){
  const[session,setSession]=useState(null),[context,setContext]=useState(null),[ready,setReady]=useState(false),[routeTick,setRouteTick]=useState(0)
  useEffect(()=>{
    let live=true
    supabase.auth.getSession().then(({data})=>{if(live){setSession(data.session??null);setReady(true)}})
    const{data}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next))
    return()=>{live=false;data.subscription.unsubscribe()}
  },[])
  useEffect(()=>{if(!session){setContext(null);return}api.context().then(setContext).catch(()=>setContext(null))},[session])
  useEffect(()=>{
    const onHash=()=>setRouteTick(v=>v+1)
    addEventListener('hashchange',onHash)
    return()=>removeEventListener('hashchange',onHash)
  },[])
  useEffect(()=>{
    const rank=Number(context?.role_rank||0)
    ensureNav(rank)
    const observer=new MutationObserver(()=>ensureNav(rank))
    observer.observe(document.body,{childList:true,subtree:true})
    return()=>observer.disconnect()
  },[context,routeTick])
  if(!ready||!session||!isActive())return null
  const rank=Number(context?.role_rank||0)
  if(rank<6)return <AccessDenied/>
  return <AccessWorkspace actorId={String(context?.user_id||'')} role={context?.role||'platform_admin'}/>
}

function AccessDenied(){return <div className="ar-overlay"><div className="ar-denied"><LockKeyhole size={30}/><h1>Platform Admin required</h1><p>User and role administration is restricted to Platform Admin rank 6.</p><button onClick={()=>goAdmin()}><ArrowLeft size={15}/>Back to Admin</button></div></div>}

function AccessWorkspace({actorId,embedded=false}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(true),[error,setError]=useState(''),[notice,setNotice]=useState(''),[query,setQuery]=useState(''),[createOpen,setCreateOpen]=useState(false),[editUser,setEditUser]=useState(null),[actingId,setActingId]=useState('')
  const load=()=>{setBusy(true);setError('');accessApi.list().then(setData).catch(e=>setError(e.message||String(e))).finally(()=>setBusy(false))}
  useEffect(load,[])
  const users=data?.users||[],roles=data?.roles||[],events=data?.events||[]
  const filtered=useMemo(()=>{const q=query.trim().toLowerCase();if(!q)return users;return users.filter(user=>[user.email,user.effective_role?.name,user.effective_role?.code,...(user.roles||[]).map(r=>r.role_name||r.role_code)].filter(Boolean).some(v=>String(v).toLowerCase().includes(q)))},[users,query])
  const active=users.filter(u=>!u.disabled).length,disabled=users.length-active,platformAdmins=users.filter(u=>!u.disabled&&(u.roles||[]).some(r=>r.role_code==='platform_admin'&&r.active)).length

  async function createUser(payload){setError('');setNotice('');try{await accessApi.create(payload);setCreateOpen(false);setNotice(payload.mode==='password'?'User created. The password is not stored or retrievable from CourseFinder.':'Invitation created and role assignment recorded.');await load()}catch(e){setError(e.message||String(e));throw e}}
  async function saveRoles(payload){setError('');setNotice('');try{await accessApi.replaceRoles(payload);setEditUser(null);setNotice('Role assignments updated. Effective access follows the highest active role.');await load()}catch(e){setError(e.message||String(e));throw e}}
  async function toggleDisabled(user){const next=!user.disabled;const verb=next?'disable':'re-enable';if(!confirm(`${verb[0].toUpperCase()+verb.slice(1)} ${user.email}?`))return;setActingId(user.id);setError('');setNotice('');try{await accessApi.setDisabled(user.id,next);setNotice(next?'Account disabled. Existing access tokens expire normally; new sign-in is blocked.':'Account re-enabled.');await load()}catch(e){setError(e.message||String(e))}finally{setActingId('')}}

  return <div className={`ar-overlay${embedded?' ar-embedded':''}`}><div className="ar-shell">
    <aside className="ar-rail"><div className="ar-brand"><span>CF</span><div><strong>Coursefinder</strong><small>Access Admin v1.0</small></div></div><div className="ar-rail-copy"><ShieldCheck size={18}/><div><strong>Platform administration</strong><small>Auth identities, governed roles and access audit.</small></div></div><nav><button className="active"><UsersRound size={16}/>Users & Roles</button></nav><div className="ar-rail-foot"><small>Authority</small><strong>Platform Admin</strong><button onClick={()=>goAdmin()}><ArrowLeft size={15}/>Back to Admin</button></div></aside>
    <main className="ar-main"><header className="ar-topbar"><div><div className="ar-eyebrow">Privileged identity administration · rank 6</div><h1>Users & Roles</h1><p>Supabase Auth identities with governed CourseFinder role assignments. Effective access is the highest active role.</p></div><div className="ar-actions"><button className="ar-secondary" onClick={load} disabled={busy}><RefreshCw size={16}/>Refresh</button><button className="ar-primary" onClick={()=>setCreateOpen(true)}><UserPlus size={16}/>Create user</button><button className="ar-secondary" onClick={()=>goAdmin()}><ArrowLeft size={16}/>Admin</button></div></header>
    {error&&<div className="ar-alert error"><AlertTriangle size={16}/><span>{prettyError(error)}</span><button onClick={()=>setError('')}><X size={15}/></button></div>}
    {notice&&<div className="ar-alert success"><Check size={16}/><span>{notice}</span><button onClick={()=>setNotice('')}><X size={15}/></button></div>}
    <section className="ar-policy"><ShieldCheck size={20}/><div><strong>Service-role stays server-side</strong><p>The browser sends only the signed-in staff JWT to a role-checked Edge Function. Passwords are never written to the access audit trail.</p></div></section>
    <section className="ar-metrics"><Metric label="Auth users" value={users.length}/><Metric label="Enabled" value={active}/><Metric label="Disabled" value={disabled}/><Metric label="Active Platform Admins" value={platformAdmins}/><Metric label="Governed roles" value={roles.length}/></section>
    <section className="ar-panel"><div className="ar-panel-head"><div><h2>User directory</h2><p>Create, invite, assign roles and disable accounts without opening the Supabase Dashboard.</p></div><label className="ar-search"><Search size={15}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search email or role"/></label></div>
      {busy&&!data?<UserSkeleton/>:<div className="ar-table-wrap"><table className="ar-table"><thead><tr><th>User</th><th>Auth state</th><th>Assigned roles</th><th>Effective role</th><th>Last sign-in</th><th>Actions</th></tr></thead><tbody>{filtered.length?filtered.map(user=><tr key={user.id}><td><strong>{user.email||'No email'}</strong><small>{shortId(user.id)}</small>{user.id===actorId&&<em className="ar-you">You</em>}</td><td><Status user={user}/></td><td><RoleChips assignments={user.roles}/></td><td>{user.effective_role?<span className={`ar-effective rank-${user.effective_role.rank}`}>{user.effective_role.name}</span>:<span className="ar-muted">Unassigned</span>}</td><td><strong>{formatDate(user.last_sign_in_at)||'Never'}</strong><small>Created {formatDate(user.created_at)||'—'}</small></td><td><div className="ar-row-actions"><button onClick={()=>setEditUser(user)}><UserCog size={14}/>Roles</button><button className={user.disabled?'enable':'disable'} disabled={actingId===user.id||user.id===actorId} title={user.id===actorId?'Self-disable is blocked':''} onClick={()=>toggleDisabled(user)}>{user.disabled?'Enable':'Disable'}</button></div></td></tr>):<tr><td colSpan="6"><div className="ar-empty">No users match this search.</div></td></tr>}</tbody></table></div>}
    </section>
    <section className="ar-panel"><div className="ar-panel-head"><div><h2>Recent access changes</h2><p>Server-side audit events. Passwords and tokens are excluded by contract.</p></div></div><AuditEvents events={events}/></section>
    </main>
    {createOpen&&<AccessModal title="Create user" roles={roles} mode="create" onClose={()=>setCreateOpen(false)} onSubmit={createUser}/>} 
    {editUser&&<AccessModal title={`Edit roles · ${editUser.email}`} roles={roles} mode="edit" user={editUser} actorId={actorId} onClose={()=>setEditUser(null)} onSubmit={saveRoles}/>} 
  </div></div>
}

export function AccessRolesEmbedded({actorId}){return <AccessWorkspace actorId={actorId} embedded/>}

function Metric({label,value}){return <div className="ar-metric"><small>{label}</small><strong>{Number(value||0).toLocaleString()}</strong></div>}
function Status({user}){if(user.disabled)return <div className="ar-status disabled"><span/>Disabled<small>{user.banned_until?`Until ${formatDate(user.banned_until)}`:''}</small></div>;if(!user.email_confirmed_at)return <div className="ar-status invited"><span/>Invited<small>Confirmation pending</small></div>;return <div className="ar-status enabled"><span/>Enabled<small>Confirmed</small></div>}
function RoleChips({assignments=[]}){if(!assignments.length)return <span className="ar-muted">No CourseFinder role</span>;return <div className="ar-role-chips">{assignments.map(a=><span key={a.role_code} className={!a.active?'expired':''} title={a.expires_at?`Expires ${formatDate(a.expires_at)}`:'No expiry'}>{a.role_name||humanise(a.role_code)}{!a.active?' · expired':''}</span>)}</div>}

function AuditEvents({events=[]}){if(!events.length)return <div className="ar-empty">No access-management events recorded yet.</div>;return <div className="ar-audit-list">{events.slice(0,30).map(event=><div className="ar-audit-row" key={event.id}><span className="ar-audit-icon"><KeyRound size={14}/></span><div><strong>{humanise(event.action)}</strong><p>{event.target_email||shortId(event.target_user_id)} · by {event.actor_email||shortId(event.actor_user_id)}</p></div><time>{formatDateTime(event.created_at)}</time></div>)}</div>}

function AccessModal({title,roles,mode,user,actorId,onClose,onSubmit}){
  const initialRoles=mode==='edit'?(user?.roles||[]).filter(r=>r.active).map(r=>r.role_code):['viewer']
  const initialExpiry=mode==='edit'?commonExpiry((user?.roles||[]).filter(r=>r.active)):''
  const[email,setEmail]=useState(mode==='edit'?user?.email||'':''),[creationMode,setCreationMode]=useState('invite'),[password,setPassword]=useState(''),[selected,setSelected]=useState(initialRoles),[expiry,setExpiry]=useState(initialExpiry),[busy,setBusy]=useState(false),[localError,setLocalError]=useState('')
  const self=mode==='edit'&&user?.id===actorId,hasPlatform=selected.includes('platform_admin')
  function toggle(code){if(self&&code==='platform_admin')return;setSelected(current=>current.includes(code)?current.filter(x=>x!==code):[...current,code]);if(code==='platform_admin'&&!selected.includes(code))setExpiry('')}
  async function submit(e){e.preventDefault();setLocalError('');if(!selected.length){setLocalError('Select at least one CourseFinder role.');return}if(mode==='create'&&creationMode==='password'&&password.length<12){setLocalError('Direct-create passwords require at least 12 characters.');return}setBusy(true);try{const expiresAt=expiry?new Date(expiry).toISOString():null;if(mode==='create')await onSubmit({email,mode:creationMode,password,roles:selected,expiresAt});else await onSubmit({userId:user.id,roles:selected,expiresAt})}catch(e){setLocalError(prettyError(e.message||String(e)))}finally{setBusy(false)}}
  return <div className="ar-modal-backdrop" role="presentation"><form className="ar-modal" onSubmit={submit}><header><div><h2>{title}</h2><p>{mode==='create'?'Invitation is recommended for staff. Password mode is intended for controlled UAT identities.':'Replacing assignments preserves the existing highest-active-role authorization model.'}</p></div><button type="button" className="ar-icon" onClick={onClose}><X size={18}/></button></header>
    {localError&&<div className="ar-alert error compact"><AlertTriangle size={15}/><span>{localError}</span></div>}
    {mode==='create'&&<><label>Email<input type="email" required value={email} onChange={e=>setEmail(e.target.value)} placeholder="user@example.com"/></label><div className="ar-mode-grid"><label className={creationMode==='invite'?'selected':''}><input type="radio" name="mode" checked={creationMode==='invite'} onChange={()=>setCreationMode('invite')}/><UserPlus size={17}/><span><strong>Send invitation</strong><small>Recommended staff workflow</small></span></label><label className={creationMode==='password'?'selected':''}><input type="radio" name="mode" checked={creationMode==='password'} onChange={()=>setCreationMode('password')}/><KeyRound size={17}/><span><strong>Create with password</strong><small>Controlled UAT/test identity</small></span></label></div>{creationMode==='password'&&<label>Password<input type="password" required minLength="12" autoComplete="new-password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="Minimum 12 characters"/><small>Sent only to the protected Edge Function. Never stored in access audit.</small></label>}</>}
    <fieldset><legend>CourseFinder roles</legend><div className="ar-role-grid">{roles.map(role=><label key={role.code} className={selected.includes(role.code)?'selected':''}><input type="checkbox" checked={selected.includes(role.code)} disabled={self&&role.code==='platform_admin'} onChange={()=>toggle(role.code)}/><span className={`ar-role-rank rank-${role.rank}`}>{role.rank}</span><span><strong>{role.name}</strong><small>{role.description}</small></span></label>)}</div><p className="ar-help">Effective access is the highest active selected rank. Use one role per UAT identity unless additive access is intentionally under test.</p></fieldset>
    <label>Role expiry<input type="datetime-local" value={expiry} disabled={hasPlatform} onChange={e=>setExpiry(e.target.value)}/><small>{hasPlatform?'Platform Admin assignments cannot expire.':'Optional. The same expiry is applied to the selected role set.'}</small></label>
    {mode==='create'&&<div className="ar-uat-hint"><Clock3 size={16}/><p>For the automated Data Quality UAT account, choose <strong>Create with password</strong> + <strong>Curator</strong>.</p></div>}
    <footer><button type="button" className="ar-secondary" onClick={onClose}>Cancel</button><button className="ar-primary" disabled={busy}>{busy?'Saving…':mode==='create'?'Create user':'Save roles'}</button></footer>
  </form></div>
}

function commonExpiry(assignments){const values=[...new Set(assignments.map(a=>a.expires_at).filter(Boolean))];if(values.length!==1)return'';const d=new Date(values[0]);if(Number.isNaN(d.getTime()))return'';const pad=n=>String(n).padStart(2,'0');return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`}
function UserSkeleton(){return <div className="ar-skeleton-list">{Array.from({length:6}).map((_,i)=><div className="ar-skeleton" key={i}/>)}</div>}
function shortId(value){const v=String(value||'');return v?`${v.slice(0,8)}…${v.slice(-4)}`:'—'}
function humanise(value){return String(value||'').replace(/[_-]+/g,' ').replace(/\b\w/g,m=>m.toUpperCase())}
function formatDate(value){if(!value)return'';const d=new Date(value);if(Number.isNaN(d.getTime()))return'';return d.toLocaleDateString('en-AU',{day:'2-digit',month:'short',year:'numeric'})}
function formatDateTime(value){if(!value)return'';const d=new Date(value);if(Number.isNaN(d.getTime()))return'';return d.toLocaleString('en-AU',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'})}
function prettyError(value){return String(value||'Unexpected error').replace(/^Error:\s*/,'').replace(/_/g,' ').replace(/\b\w/g,m=>m.toUpperCase())}

if(root)root.render(<AccessBootstrap/>)
