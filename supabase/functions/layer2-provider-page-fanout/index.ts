import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION="layer2-provider-page-fanout-v1.4";
const BUCKET="evidence";
const ORIGIN="https://coursefinder-pilot.techm.workers.dev";

const H=(r:Request)=>({
  "content-type":"application/json",
  "cache-control":"no-store",
  "access-control-allow-origin":r.headers.get("origin")===ORIGIN?ORIGIN:ORIGIN,
  "access-control-allow-headers":"authorization,content-type,x-cf-pilot-key",
  "access-control-allow-methods":"POST,OPTIONS"
});
const J=(r:Request,s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:H(r)});
const clean=(x:any)=>String(x??"").replace(/\s+/g," ").trim();

async function rpc(c:any,n:string,a:any={}){
  const{data,error}=await c.rpc(n,a);
  if(error)throw Error(n+": "+error.message);
  return data;
}
async function auth(req:Request,svc:any,sb:string,anon:string){
  const key=(req.headers.get("x-cf-pilot-key")||"").trim();
  if(key){
    if(await rpc(svc,"svc_pilot_automation_authorize",{p_key:key})!==true)throw Error("invalid_pilot_automation_key");
    return;
  }
  const ah=req.headers.get("authorization")||"";
  if(!/^Bearer /i.test(ah))throw Error("authentication_required");
  const u=createClient(sb,anon,{global:{headers:{Authorization:ah}},auth:{persistSession:false}});
  const{data:ctx,error}=await u.rpc("admin_read",{p_operation:"context",p_args:{}});
  if(error||!ctx?.authenticated)throw Error("authentication_required");
  if(Number(ctx.role_rank||0)<4)throw Error("pipeline_operator_role_required");
}
function htmlFrom(raw:string,mime:string){
  if(mime.includes("json")){
    try{
      const j=JSON.parse(raw),d=j?.data||j;
      return String(d?.html||d?.rawHtml||d?.content||d?.markdown||"");
    }catch{return raw}
  }
  return raw;
}
function abs(base:string,href:string){
  try{return new URL(href,base).toString()}catch{return null}
}
function attr(tag:string,name:string){
  const m=tag.match(new RegExp(name+"\\s*=\\s*([\"'])([\\s\\S]*?)\\1","i"));
  return m?clean(m[2]):null;
}
function providerSignals(providerName:string){
  const stop=new Set(["university","college","limited","australia","australian","the","of"]);
  const words=clean(providerName).toLowerCase().split(/[^a-z0-9]+/).filter((x:string)=>x.length>=4&&!stop.has(x));
  const initials=clean(providerName).split(/[^A-Za-z0-9]+/).filter((x:string)=>x.length>2&&!stop.has(x.toLowerCase())).map((x:string)=>x[0]).join("").toLowerCase();
  return{words,initials};
}
function logoCandidates(html:string,base:string,providerName:string){
  const out:any[]=[];
  const sig=providerSignals(providerName);
  const add=(url:string|null,score:number,kind:string,alt:string="",selector_hint:string="")=>{
    if(!url)return;const u=abs(base,url);if(!u)return;
    const s=(u+" "+alt+" "+selector_hint).toLowerCase(),compact=s.replace(/[^a-z0-9]/g,"");
    let x=score;
    if(/logo|brand|wordmark|crest/.test(s))x+=0.20;
    if(/header|navbar|navigation|site-logo|navigationlogo|masthead/.test(s))x+=0.15;
    if(sig.words.some((t:string)=>s.includes(t)))x+=0.18;
    if(sig.initials.length>=2&&compact.includes(sig.initials))x+=0.10;
    if(/footer/.test(s))x-=0.10;
    if(/partnership|partner|alliance|network|sponsor/.test(s))x-=0.40;
    if(/avatar|social|facebook|instagram|youtube|linkedin|twitter|x-logo/.test(s))x-=0.45;
    if(/favicon|apple-touch-icon/.test(s))x-=0.20;
    if(/\.svg(?:[?#]|$)/i.test(u))x+=0.05;
    x=Math.max(0,Math.min(0.99,x));
    if(x>=0.55)out.push({url:u,score:x,kind,alt,selector_hint});
  };
  for(const m of html.matchAll(/<img\b[^>]*>/gi)){
    const tag=m[0],src=attr(tag,"src")||attr(tag,"data-src")||attr(tag,"data-lazy-src");
    const alt=clean(attr(tag,"alt")||""),cls=clean(attr(tag,"class")||""),id=clean(attr(tag,"id")||"");
    if(src)add(src,0.35,"img",alt,clean([id,cls].filter(Boolean).join(" ")));
    const srcset=attr(tag,"srcset")||attr(tag,"data-srcset");
    if(srcset){const first=clean(srcset.split(",")[0]?.trim().split(/\s+/)[0]||"");if(first)add(first,0.32,"img-srcset",alt,clean([id,cls].filter(Boolean).join(" ")))}
  }
  for(const m of html.matchAll(/<(?:source|object|embed)\b[^>]*>/gi)){
    const tag=m[0],src=attr(tag,"src")||attr(tag,"data")||attr(tag,"srcset");
    if(src){const first=clean(src.split(",")[0]?.trim().split(/\s+/)[0]||"");add(first,0.35,"structured-image","",clean((attr(tag,"class")||"")+" "+(attr(tag,"id")||"")))}
  }
  for(const m of html.matchAll(/<(?:a|div|span|header)\b[^>]*(?:class|id)\s*=\s*["'][^"']*(?:logo|brand|wordmark|masthead)[^"']*["'][^>]*>[\s\S]{0,1800}?(?:<img\b[^>]*>|<use\b[^>]*>)/gi)){
    const block=m[0],img=block.match(/<img\b[^>]*>/i)?.[0]||"",use=block.match(/<use\b[^>]*>/i)?.[0]||"";
    const src=img?(attr(img,"src")||attr(img,"data-src")||attr(img,"data-lazy-src")||attr(img,"srcset")):(attr(use,"href")||attr(use,"xlink:href"));
    const hint=clean((attr(block,"class")||"")+" "+(attr(block,"id")||""));
    if(src)add(clean(src.split(",")[0]?.trim().split(/\s+/)[0]||""),0.62,"logo-container",attr(img,"alt")||"",hint);
  }
  for(const m of html.matchAll(/<meta\b[^>]*>/gi)){
    const tag=m[0],prop=(attr(tag,"property")||attr(tag,"name")||attr(tag,"itemprop")||"").toLowerCase();
    const content=attr(tag,"content")||"";
    if(prop==="logo")add(content,0.78,"meta-logo");
    else if(prop==="og:image"||prop==="twitter:image")add(content,0.25,prop);
  }
  for(const m of html.matchAll(/<link\b[^>]*>/gi)){
    const tag=m[0],rel=(attr(tag,"rel")||"").toLowerCase(),href=attr(tag,"href")||"";
    if(/logo|brand/.test(tag.toLowerCase()))add(href,0.60,"link-logo");
    else if(/icon/.test(rel))add(href,0.32,"site-icon");
  }
  for(const m of html.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)){
    try{
      const root=JSON.parse(m[1]);
      const walk=(v:any)=>{
        if(!v)return;
        if(Array.isArray(v)){v.forEach(walk);return}
        if(typeof v!=="object")return;
        const typ=String(v["@type"]||"").toLowerCase();
        if(typ.includes("organization")||typ.includes("college")||typ.includes("university")||typ.includes("educationalorganization")){
          const logo=v.logo;
          if(typeof logo==="string")add(logo,0.80,"jsonld-logo");
          else if(logo&&typeof logo==="object")add(logo.url||logo.contentUrl,0.80,"jsonld-logo",String(logo.caption||""));
        }
        Object.values(v).forEach(walk);
      };
      walk(root);
    }catch{}
  }
  for(const m of html.matchAll(/(?:background-image\s*:\s*url\(|["'])([^"'()\s>]{1,500}(?:logo|wordmark|brand)[^"'()\s>]*\.(?:svg|png|webp|jpe?g)(?:\?[^"'()\s>]*)?)/gi))add(m[1],0.48,"markup-logo-url");
  const best=new Map<string,any>();
  for(const x of out){const key=x.url.split("#")[0];const p=best.get(key);if(!p||x.score>p.score)best.set(key,x)}
  return [...best.values()].sort((a,b)=>b.score-a.score).slice(0,12);
}
function scholarshipLinks(html:string,base:string){
  const out:any[]=[];
  for(const m of html.matchAll(/<a\b[^>]*href\s*=\s*([\"'])([\s\S]*?)\1[^>]*>([\s\S]*?)<\/a>/gi)){
    const href=clean(m[2]),text=clean(m[3].replace(/<[^>]+>/g," "));
    const u=abs(base,href);if(!u)continue;
    const s=(u+" "+text).toLowerCase();
    if(!/(scholar|bursar|financial[- ]?aid|funding|award)/.test(s))continue;
    if(/news|event|donat|alumni|research[- ]?award|staff[- ]?award|reporter/.test(s))continue;
    out.push({url:u,title:text.slice(0,240)||null});
  }
  const seen=new Set<string>();
  return out.filter(x=>!seen.has(x.url)&&seen.add(x.url)).slice(0,30);
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:H(req)});
  if(req.method!=="POST")return J(req,405,{error:"method_not_allowed"});
  const sb=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const svc=createClient(sb,sk,{auth:{persistSession:false}});
  try{await auth(req,svc,sb,anon)}catch(e:any){return J(req,String(e.message).includes("role")?403:401,{error:String(e.message)})}
  const b=await req.json().catch(()=>({})),sfid=String(b.shared_fetch_id||"");
  if(!sfid)return J(req,400,{error:"shared_fetch_id_required"});
  let ctx:any;
  try{ctx=await rpc(svc,"layer2_shared_fetch_fanout_context",{p_shared_fetch_id:sfid})}
  catch(e:any){return J(req,500,{error:"fanout_context_failed",detail:String(e.message)})}
  if(!ctx?.evidence_id)return J(req,404,{error:"shared_fetch_not_found"});
  const{data:blob,error:de}=await svc.storage.from(BUCKET).download(String(ctx.storage_path||""));
  if(de||!blob)return J(req,500,{error:"evidence_download_failed",detail:de?.message||null});
  const raw=await blob.text(),html=htmlFrom(raw,String(ctx.mime_type||""));
  if(!html)return J(req,422,{error:"html_not_available"});
  const base=String(ctx.source_url||"");
  const logos=logoCandidates(html,base,String(ctx.provider_name||"")),links=scholarshipLinks(html,base);
  let applied:any;
  try{
    applied=await rpc(svc,"layer2_provider_page_fanout_apply",{p_shared_fetch_id:sfid,p_logo_candidates:logos,p_scholarship_links:links});
  }catch(e:any){
    return J(req,500,{error:"fanout_apply_failed",detail:String(e.message)});
  }
  return J(req,200,{
    ok:true,
    worker_version:VERSION,
    shared_fetch_id:sfid,
    provider_id:ctx.provider_id,
    logo_candidates:logos.length,
    scholarship_links:links.length,
    top_logo:logos[0]||null,
    applied
  });
});