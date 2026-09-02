import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION="layer2-provider-page-fanout-v1";
const BUCKET="evidence";
const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
const H=(r:Request)=>({"content-type":"application/json","cache-control":"no-store","access-control-allow-origin":r.headers.get("origin")===ORIGIN?ORIGIN:ORIGIN,"access-control-allow-headers":"authorization,content-type,x-cf-pilot-key","access-control-allow-methods":"POST,OPTIONS"});
const J=(r:Request,s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:H(r)});
const clean=(x:any)=>String(x??"").replace(/\s+/g," ").trim();
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw Error(n+": "+error.message);return data}
async function auth(req:Request,svc:any,sb:string,anon:string){
 const key=(req.headers.get("x-cf-pilot-key")||"").trim();
 if(key){if(await rpc(svc,"svc_pilot_automation_authorize",{p_key:key})!==true)throw Error("invalid_pilot_automation_key");return}
 const ah=req.headers.get("authorization")||"";if(!/^Bearer /i.test(ah))throw Error("authentication_required");
 const u=createClient(sb,anon,{global:{headers:{Authorization:ah}},auth:{persistSession:false}});
 const{data:ctx,error}=await u.rpc("admin_read",{p_operation:"context",p_args:{}});
 if(error||!ctx?.authenticated)throw Error("authentication_required");if(Number(ctx.role_rank||0)<4)throw Error("pipeline_operator_role_required");
}
function htmlFrom(raw:string,mime:string){
 if(mime.includes("json")){try{const j=JSON.parse(raw);const d=j?.data||j;return String(d?.html||d?.rawHtml||d?.content||d?.markdown||"")}catch{return raw}}
 return raw;
}
function abs(base:string,href:string){try{return new URL(href,base).toString()}catch{return null}}
function attr(tag:string,name:string){const m=tag.match(new RegExp(name+"\\s*=\\s*([\"'])([\\s\\S]*?)\\1","i"));return m?clean(m[2]):null}
function logoCandidates(html:string,base:string){
 const out:any[]=[];
 for(const m of html.matchAll(/<img\b[^>]*>/gi)){
  const tag=m[0],src=attr(tag,"src")||attr(tag,"data-src")||attr(tag,"data-lazy-src");if(!src)continue;
  const alt=clean(attr(tag,"alt")||""),cls=clean(attr(tag,"class")||""),id=clean(attr(tag,"id")||"");
  const u=abs(base,src);if(!u)continue;const s=(u+" "+alt+" "+cls+" "+id).toLowerCase();
  let score=0.35;if(/logo|brand|wordmark|crest/.test(s))score+=0.45;if(/header|navbar|site-logo/.test(s))score+=0.15;if(/footer/.test(s))score-=0.05;if(/avatar|icon|favicon|social|facebook|instagram|youtube|linkedin|twitter|x-logo/.test(s))score-=0.35;
  if(/\.svg(?:\?|$)/i.test(u))score+=0.08;if(/\.png(?:\?|$)/i.test(u))score+=0.04;
  if(score>=0.55)out.push({url:u,score:Math.max(0,Math.min(0.99,score)),kind:"img",alt,selector_hint:clean([id,cls].filter(Boolean).join(" "))});
 }
 for(const m of html.matchAll(/<meta\b[^>]*>/gi)){
  const tag=m[0],prop=(attr(tag,"property")||attr(tag,"name")||"").toLowerCase();
  if(prop!=="og:image"&&prop!=="twitter:image")continue;const u=abs(base,attr(tag,"content")||"");if(u)out.push({url:u,score:0.45,kind:prop});
 }
 for(const m of html.matchAll(/<link\b[^>]*>/gi)){
  const tag=m[0],rel=(attr(tag,"rel")||"").toLowerCase();if(!/icon/.test(rel))continue;const u=abs(base,attr(tag,"href")||"");if(u)out.push({url:u,score:0.25,kind:"icon"});
 }
 const best=new Map<string,any>();for(const x of out){const p=best.get(x.url);if(!p||x.score>p.score)best.set(x.url,x)}
 return [...best.values()].sort((a,b)=>b.score-a.score).slice(0,12);
}
function scholarshipLinks(html:string,base:string){
 const out:any[]=[];
 for(const m of html.matchAll(/<a\b[^>]*href\s*=\s*([\"'])([\s\S]*?)\1[^>]*>([\s\S]*?)<\/a>/gi)){
  const href=clean(m[2]),text=clean(m[3].replace(/<[^>]+>/g," "));const u=abs(base,href);if(!u)continue;
  const sig=(u+" "+text).toLowerCase();if(!/(scholar|bursar|financial[- ]?aid|funding|award)/.test(sig))continue;
  if(/news|event|donat|alumni|research[- ]?award|staff[- ]?award/.test(sig))continue;
  out.push({url:u,title:text.slice(0,240)||null});
 }
 const seen=new Set<string>();return out.filter(x=>!seen.has(x.url)&&seen.add(x.url)).slice(0,30);
}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:H(req)});if(req.method!=="POST")return J(req,405,{error:"method_not_allowed"});
 const sb=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
 const svc=createClient(sb,sk,{auth:{persistSession:false}});
 try{await auth(req,svc,sb,anon)}catch(e:any){return J(req,String(e.message).includes("role")?403:401,{error:String(e.message)})}
 const b=await req.json().catch(()=>({}));const sfid=String(b.shared_fetch_id||"");if(!sfid)return J(req,400,{error:"shared_fetch_id_required"});
 const{data:f,error:fe}=await svc.schema("pipeline").from("layer2_shared_fetches").select("id,source_url,evidence_id,source_profile_id,content_hash,mime_type").eq("id",sfid).single();
 if(fe||!f)return J(req,404,{error:"shared_fetch_not_found"});
 const{data:e,error:ee}=await svc.schema("pipeline").from("evidence_artifacts").select("id,source_id,storage_path,mime_type,content_hash,source_profile_version_id").eq("id",f.evidence_id).single();
 if(ee||!e)return J(req,404,{error:"evidence_not_found"});
 const{data:s,error:se}=await svc.schema("pipeline").from("sources").select("id,provider_id,url").eq("id",e.source_id).single();
 if(se||!s?.provider_id)return J(req,409,{error:"provider_source_required"});
 const{data:blob,error:de}=await svc.storage.from(BUCKET).download(e.storage_path);if(de||!blob)return J(req,500,{error:"evidence_download_failed"});
 const raw=await blob.text(),html=htmlFrom(raw,String(e.mime_type||f.mime_type||""));if(!html)return J(req,422,{error:"html_not_available"});
 const base=String(f.source_url||s.url||"");
 const logos=logoCandidates(html,base),links=scholarshipLinks(html,base);
 const{data:profiles}=await svc.schema("pipeline").from("layer2_source_profiles").select("id,domain,current_version_id").eq("source_id",e.source_id).in("domain",["provider_asset","scholarship"]);
 const logoProfile=profiles?.find((x:any)=>x.domain==="provider_asset"),schProfile=profiles?.find((x:any)=>x.domain==="scholarship");
 let logoInserted=0,schInserted=0;
 for(const x of logos){
  const{error}=await svc.schema("pipeline").from("provider_asset_candidates").upsert({
   provider_id:s.provider_id,profile_id:logoProfile?.id||null,source_url:base,asset_url:x.url,asset_type:"logo",evidence_id:e.id,content_hash:null,
   confidence:x.score,status:x.score>=0.88?"accepted":x.score>=0.65?"needs_review":"discovered",
   metadata:{worker_version:VERSION,kind:x.kind,alt:x.alt||null,selector_hint:x.selector_hint||null,canonical_mutation_authorised:false}
  },{onConflict:"provider_id,asset_url",ignoreDuplicates:false});if(!error)logoInserted++;
 }
 for(const x of links){
  const{error}=await svc.schema("pipeline").from("layer2_scholarship_discovery_candidates").upsert({
   source_id:e.source_id,evidence_id:e.id,source_profile_version_id:schProfile?.current_version_id||null,scholarship_url:x.url,observed_title:x.title,status:"discovered"
  },{onConflict:"evidence_id,scholarship_url",ignoreDuplicates:true});if(!error)schInserted++;
 }
 await svc.schema("pipeline").from("layer2_fanout_tasks").update({status:"completed",completed_at:new Date().toISOString(),metadata:{worker_version:VERSION,logo_candidates:logos.length,scholarship_links:links.length}}).eq("shared_fetch_id",sfid).in("task_type",["provider_asset","scholarship_discovery"]);
 return J(req,200,{ok:true,worker_version:VERSION,shared_fetch_id:sfid,provider_id:s.provider_id,logo_candidates:logos.length,logo_rows_written:logoInserted,scholarship_links:links.length,scholarship_rows_written:schInserted,top_logo:logos[0]||null});
});