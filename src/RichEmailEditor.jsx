// Links & Email Templates › the email body editor (v2.16.35, Platform Admin 18 Nov 2026 10:31 and 10:33: "a plain-English rich formatting editor with
// toolbar support for formatting and link insertion, plus variable and magic-link chips, instead of raw code editing").
// The body is edited as formatted text in a frame of its own (sandbox without scripts, designMode): what the template's HTML styles, and anything pasted
// into it, stays inside the frame and nothing in it can run. Each edit hands the frame's HTML back to the screen, which saves it as before
// (admin_auth_template_settings_save checks {{link}}, the five variables and no script). Edit HTML shows the same body as code for a person who needs it.
import React,{useEffect,useRef,useState}from'react'
import{Bold,Code2,Heading2,Italic,Link2,List,ListOrdered,MousePointerClick,Pilcrow,RemoveFormatting,Underline}from'lucide-react'

// what each variable is called on the screen; the saved template keeps {{token}}
export const TOKEN_LABELS={link:'Sign-in link',guide_link:'Admin guide link',user_email:'Their email',user_name:'Their name',role:'Their role'}
// what is removed from pasted or loaded HTML before it is shown in the editor frame (the frame runs no script either way)
export function cleanEmailHtml(html){
  return String(html||'').replace(/<\s*(script|iframe|object|embed|form|input|button|meta|link|base)\b[^>]*>[\s\S]*?<\s*\/\s*\1\s*>/gi,'').replace(/<\s*(script|iframe|object|embed|form|input|button|meta|link|base)\b[^>]*\/?>/gi,'')
    .replace(/\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi,'').replace(/(href|src)\s*=\s*(["'])\s*javascript:[^"']*\2/gi,'$1="#"')
}
// a safe web address for a link the person types: https only, or one of the two link variables
export const linkTarget=v=>{const t=String(v||'').trim();if(t==='{{link}}'||t==='{{guide_link}}')return t;return/^https:\/\/[^\s"'<>]+$/i.test(t)?t:''}
const escText=v=>String(v??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
const escAttr=v=>escText(v).replace(/"/g,'&quot;')

export default function RichEmailEditor({value,onChange,onFocus,resetKey,codeView=false,onCodeView,onTokenCode,tokens=Object.keys(TOKEN_LABELS),label='Email body'}){
  const html=codeView,setHtml=f=>onCodeView?.(typeof f==='function'?f(html):f)
  const frame=useRef(null),[linkOpen,setLinkOpen]=useState(false),[href,setHref]=useState('{{link}}'),[text,setText]=useState(''),[warn,setWarn]=useState(''),saved=useRef(null)
  const doc=()=>frame.current?.contentDocument
  // the body is written into the frame when the template changes (another template, Reset to Default) or HTML mode closes, never on each keystroke
  useEffect(()=>{const d=doc();if(!d||html)return
    d.open();d.write(`<!doctype html><html><head><meta charset="utf-8"><style>body{margin:12px;font:15px/1.5 Arial,Helvetica,sans-serif}</style></head><body>${cleanEmailHtml(value)}</body></html>`);d.close()
    d.designMode='on'
    const emit=()=>onChange?.(cleanEmailHtml(d.body.innerHTML))
    d.addEventListener('input',emit);d.addEventListener('focus',()=>onFocus?.(),true);d.addEventListener('mousedown',()=>onFocus?.())
    d.addEventListener('paste',e=>{const t=e.clipboardData?.getData('text/html');if(t){e.preventDefault();d.execCommand('insertHTML',false,cleanEmailHtml(t))}})
    return()=>{d.removeEventListener('input',emit)}},[resetKey,html])
  const run=(cmd,arg=null)=>{const d=doc();if(!d)return;d.body.focus();d.execCommand(cmd,false,arg);onChange?.(cleanEmailHtml(d.body.innerHTML))}
  const keep=()=>{const d=doc();const s=d?.getSelection?.();saved.current=s&&s.rangeCount?s.getRangeAt(0).cloneRange():null;setText(s?String(s):'')}
  const restore=()=>{const d=doc();const s=d?.getSelection?.();if(s&&saved.current){s.removeAllRanges();s.addRange(saved.current)}}
  const insertToken=t=>{if(html||onTokenCode?.(t)===true)return;restore();run('insertText',`{{${t}}}`)}
  function insertLink(e){e?.preventDefault?.();const target=linkTarget(href);if(!target){setWarn('Use an address that starts with https://, or choose the Sign-in link or the Admin guide link.');return}
    const words=text.trim()||(target==='{{link}}'?'Sign in to StudySearch':target==='{{guide_link}}'?'Read the Admin guide':target)
    restore();run('insertHTML',`<a href="${escAttr(target)}">${escText(words)}</a>`);setLinkOpen(false);setWarn('')}
  const insertButton=()=>{restore();run('insertHTML','<p><a href="{{link}}" style="display:inline-block;padding:12px 20px;background:black;color:white;border-radius:6px;text-decoration:none;font-weight:bold">Sign in to StudySearch</a></p>')}
  const B=({icon:Icon,title,onClick,data})=><button type="button" className="rte-btn" title={title} aria-label={title} onMouseDown={e=>e.preventDefault()} onClick={onClick} disabled={html} data-rte={data}><Icon size={15}/></button>
  return <div className="rte" data-rte-editor>
    <div className="rte-bar" role="toolbar" aria-label={`${label} formatting`}>
      <B icon={Bold} title="Bold" data="bold" onClick={()=>run('bold')}/><B icon={Italic} title="Italic" data="italic" onClick={()=>run('italic')}/><B icon={Underline} title="Underline" data="underline" onClick={()=>run('underline')}/>
      <span className="rte-sep"/><B icon={Heading2} title="Heading" data="heading" onClick={()=>run('formatBlock','h2')}/><B icon={Pilcrow} title="Paragraph" data="paragraph" onClick={()=>run('formatBlock','p')}/>
      <B icon={List} title="Bulleted list" data="ul" onClick={()=>run('insertUnorderedList')}/><B icon={ListOrdered} title="Numbered list" data="ol" onClick={()=>run('insertOrderedList')}/>
      <span className="rte-sep"/><B icon={Link2} title="Insert link" data="link" onClick={()=>{keep();setLinkOpen(x=>!x)}}/><B icon={MousePointerClick} title="Insert a Sign in button" data="button" onClick={()=>{keep();insertButton()}}/>
      <B icon={RemoveFormatting} title="Clear formatting" data="clear" onClick={()=>run('removeFormat')}/>
      <span className="rte-grow"/><button type="button" className={`rte-btn rte-html${html?' is-on':''}`} aria-pressed={html} onClick={()=>setHtml(x=>!x)} data-rte-html><Code2 size={15}/>{html?'Back to formatted text':'Edit HTML'}</button>
    </div>
    <div className="rte-chips" role="toolbar" aria-label="Insert a variable"><span className="sl-sub">Insert:</span>{tokens.map(k=><button key={k} type="button" className="aet-chip" title={`Writes {{${k}}}; replaced in each email`} onMouseDown={e=>{e.preventDefault();keep()}} onClick={()=>insertToken(k)} data-aet-token={k}>{TOKEN_LABELS[k]||k}</button>)}</div>
    {linkOpen&&!html&&<form className="rte-link" onSubmit={insertLink} data-rte-link-form>
      <label>Link to<select value={['{{link}}','{{guide_link}}'].includes(href)?href:'web'} onChange={e=>setHref(e.target.value==='web'?'https://':e.target.value)} data-rte-link-kind>
        <option value="{{link}}">Sign-in link (the magic link)</option><option value="{{guide_link}}">Admin guide link</option><option value="web">A web address</option></select></label>
      {!['{{link}}','{{guide_link}}'].includes(href)&&<label>Web address<input value={href} onChange={e=>setHref(e.target.value)} placeholder="https://" data-rte-link-url/></label>}
      <label>Words shown<input value={text} onChange={e=>setText(e.target.value)} placeholder="The selected words, or a label" data-rte-link-text/></label>
      <button type="submit" className="m-secondary compact" data-rte-link-insert>Insert link</button><button type="button" className="m-secondary compact" onClick={()=>{setLinkOpen(false);setWarn('')}}>Cancel</button>
      {warn&&<p className="aet-warn" role="alert">{warn}</p>}</form>}
    {html?null:<iframe ref={frame} title={label} className="rte-frame" sandbox="allow-same-origin" data-rte-frame/>}
  </div>
}
