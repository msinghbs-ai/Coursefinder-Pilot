import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION="layer2-scholarship-catalogue-enumerate-v1";
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
function attr(tag:string,name:string){
  const m=tag.match(new RegExp(name+"\\s*=\\s*([\"'])([\\s\\S]*?)\\1","i"));
  return m?clean(m[2]):null;
}
function visible(s:string){
  return clean(s.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi," ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi," ")
    .replace(/<[^>]+>/g," ")
    .replace(/&nbsp;/gi," ")
    .replace(/&amp;/gi,"&")
    .replace(/&quot;/gi,'"')
    .replace(/&#39;/gi,"'"));
}
function htmlFromNormalized(raw:string){
  try{
    const j=JSON.parse(raw);
    if(typeof j?.html==="string"&&j.html.trim())return j.html;
    if(typeof j?.text==="string"&&/<a\b/i.test(j.text))return j.text;
    if(typeof j?.structured?.html==="string")return j.structured.html;
    if(typeof j?.structured?.data?.html==="string")return j.structured.data.html;
    return "";
  }catch{return raw}
}
function normUrl(u:string){
  try{
    const x=new URL(u);
    x.hash="";
    for(const k of [...x.searchParams.keys()]){
      if(/^utm_|^(fbclid|gclid|mc_cid|mc_eid)$/i.test(k))x.searchParams.delete(k);
    }
    if(x.pathname.length>1)x.pathname=x.pathname.replace(/\/+$/,"");
    return x.toString();
  }catch{return u}
}
function enumerate(html:string,base:string){
  const out:any[]=[];
  const baseUrl=new URL(base);
  const baseNorm=normUrl(base);
  const basePath=baseUrl.pathname.toLowerCase();
  const baseScholarRoot=basePath.match(/^(.*?\/(?:scholarships?|financial-aid|funding|grants?))(?:\/.*)?$/i)?.[1]||null;

  for(const m of html.matchAll(/<a\b[^>]*>([\s\S]*?)<\/a>/gi)){
    const tag=m[0];
    const href=attr(tag,"href");
    if(!href||/^(mailto:|tel:|javascript:|#)/i.test(href))continue;
    let u:URL;
    try{u=new URL(href,base)}catch{continue}
    if(!/^https?:$/.test(u.protocol))continue;
    const title=visible(m[1]).slice(0,300);
    const urlNorm=normUrl(u.toString());
    if(urlNorm===baseNorm)continue;

    const hostSame=u.hostname.replace(/^www\./,"").toLowerCase()===baseUrl.hostname.replace(/^www\./,"").toLowerCase();
    const path=(u.pathname+" "+u.search).toLowerCase();
    const sig=(path+" "+title).toLowerCase();

    const positive=/(scholar|bursar|grant|award|financial[- ]?aid|tuition[- ]?(?:fee[- ]?)?(?:waiver|discount)|merit|excellence)/i.test(sig);
    const rooted=Boolean(hostSame&&baseScholarRoot&&u.pathname.toLowerCase().startsWith(baseScholarRoot)&&u.pathname.toLowerCase()!==basePath);
    if(!positive&&!rooted)continue;

    if(/\b(news|events?|stories|media|blog|policy|policies|terms|privacy|login|sign[- ]?in|apply-now|application-portal|donate|giving|alumni)\b/i.test(sig))continue;
    if(/(?:staff|employee|researcher)[-_ ]?(?:award|grant)/i.test(sig)&&!/scholar/i.test(sig))continue;
    if(title.length===0&&!positive)continue;

    let score=0.45;
    if(hostSame)score+=0.15;
    if(/scholar/i.test(path))score+=0.20;
    if(/scholar/i.test(title))score+=0.15;
    if(/international/i.test(sig))score+=0.10;
    if(rooted)score+=0.10;
    if(/learn more|read more|view details?|find out more/i.test(title))score-=0.05;

    out.push({
      url:urlNorm,
      title:title||null,
      confidence:Math.min(0.99,Math.max(0.1,score)),
      same_host:hostSame,
      source_kind:/\.pdf(?:\?|$)/i.test(urlNorm)?"pdf":"html"
    });
  }

  const best=new Map<string,any>();
  for(const x of out){
    const p=best.get(x.url);
    if(!p||x.confidence>p.confidence)best.set(x.url,x);
  }
  return [...best.values()].sort((a,b)=>b.confidence-a.confidence||String(a.url).localeCompare(String(b.url))).slice(0,500);
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:H(req)});
  if(req.method!=="POST")return J(req,405,{error:"method_not_allowed"});

  const sb=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const svc=createClient(sb,sk,{auth:{persistSession:false}});
  try{await auth(req,svc,sb,anon)}catch(e:any){
    return J(req,String(e.message).includes("role")?403:401,{error:String(e.message)});
  }

  const b=await req.json().catch(()=>({}));
  const eid=String(b.normalized_evidence_id||"");
  if(!eid)return J(req,400,{error:"normalized_evidence_id_required"});

  let ctx:any;
  try{ctx=await rpc(svc,"layer2_scholarship_extraction_context",{p_evidence_id:eid})}
  catch(e:any){return J(req,500,{error:"catalogue_context_failed",detail:String(e.message)})}
  if(!ctx?.id)return J(req,404,{error:"evidence_not_found"});
  if(ctx.evidence_type!=="layer2_extraction_input")return J(req,409,{error:"layer2_extraction_input_required"});

  const{data:blob,error:de}=await svc.storage.from(BUCKET).download(String(ctx.storage_path||""));
  if(de||!blob)return J(req,500,{error:"evidence_download_failed",detail:de?.message||null});

  const raw=await blob.text();
  const html=htmlFromNormalized(raw);
  if(!html)return J(req,422,{error:"catalogue_html_not_available"});

  const links=enumerate(html,String(ctx.source_url||""));
  const status=links.length>0?"complete":"needs_review";

  let applied:any;
  try{
    applied=await rpc(svc,"layer2_scholarship_catalogue_apply",{
      p_evidence_id:eid,
      p_links:links,
      p_status:status,
      p_metadata:{
        worker_version:VERSION,
        provider_name:ctx.provider_name||null,
        source_type:ctx.source_type||null,
        canonical_mutation_authorised:false
      }
    });
  }catch(e:any){
    return J(req,500,{error:"catalogue_apply_failed",detail:String(e.message)});
  }

  return J(req,200,{
    ok:true,
    worker_version:VERSION,
    normalized_evidence_id:eid,
    provider_id:ctx.provider_id,
    provider_name:ctx.provider_name,
    source_url:ctx.source_url,
    catalogue_status:status,
    discovered_links:links.length,
    top_links:links.slice(0,12),
    applied,
    canonical_mutation_authorised:false
  });
});