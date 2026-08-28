import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";
const FN="layer2-screenshot-backfill-scheduled",BUCKET="evidence",VERSION="layer2-screenshot-backfill-scheduled-v1.0.0";
const J=(s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
const clean=(v:any)=>String(v??"").trim();
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw new Error(`${n}: ${error.message}`);return data}
async function hash(bytes:Uint8Array){const d=await crypto.subtle.digest("SHA-256",bytes);return[...new Uint8Array(d)].map(x=>x.toString(16).padStart(2,"0")).join("")}
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return J(405,{ok:false,error:"POST required",worker_version:VERSION});
 const sb=Deno.env.get("SUPABASE_URL")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,svc=createClient(sb,sk,{auth:{persistSession:false}});
 try{
  const nonce=clean(req.headers.get("x-cf-run-nonce"));if(!nonce)throw new Error("one-time schedule nonce required");
  if(!await rpc(svc,"svc_pilot_consume_nonce",{p_function:FN,p_nonce:nonce}))throw new Error("invalid, expired or already-used schedule nonce");
  const b=await req.json().catch(()=>({})),evidenceId=clean(b.evidence_id);if(!evidenceId)throw new Error("evidence_id required");
  const ctx=await rpc(svc,"layer2_screenshot_backfill_context",{p_evidence_id:evidenceId});if(!ctx?.attempt_id||!ctx?.source_url)throw new Error("eligible source attempt not found");
  if(ctx.existing_screenshot_evidence_id)return J(200,{ok:true,status:"already_present",evidence_id:evidenceId,screenshot_evidence_id:ctx.existing_screenshot_evidence_id,worker_version:VERSION});
  const providerId=await rpc(svc,"svc_layer2_trial_provider_id",{p_provider_key:"firecrawl"}),pc=await rpc(svc,"layer2_provider_runtime_config",{p_provider_id:providerId});
  if(!pc?.enabled||!pc?.secret)throw new Error("Firecrawl provider unavailable");
  const ctl=new AbortController(),tm=setTimeout(()=>ctl.abort(),30000);let res:Response;
  try{res=await fetch(String(pc.base_url),{method:"POST",signal:ctl.signal,headers:{"authorization":"Bearer "+pc.secret,"content-type":"application/json"},body:JSON.stringify({url:ctx.source_url,formats:["screenshot"]})})}finally{clearTimeout(tm)}
  const payload=await res.json().catch(()=>({}));if(!res.ok)throw new Error(`Firecrawl ${res.status}: ${JSON.stringify(payload).slice(0,500)}`);
  const d=payload?.data||payload,surl=clean(d?.screenshot||d?.screenshotUrl||d?.metadata?.screenshot);if(!surl)throw new Error("Firecrawl screenshot URL not returned");
  const u=new URL(surl);if(u.protocol!=="https:")throw new Error("Firecrawl screenshot URL invalid");
  const ictl=new AbortController(),itm=setTimeout(()=>ictl.abort(),20000);let img:Response;
  try{img=await fetch(u.toString(),{signal:ictl.signal,redirect:"follow",headers:{"accept":"image/png,image/jpeg,image/webp"}})}finally{clearTimeout(itm)}
  if(!img.ok)throw new Error(`screenshot download ${img.status}`);
  const mime=(img.headers.get("content-type")||"image/png").split(";")[0].trim().toLowerCase();if(!["image/png","image/jpeg","image/webp"].includes(mime))throw new Error("unexpected screenshot MIME "+mime);
  const bytes=new Uint8Array(await img.arrayBuffer()),digest=await hash(bytes),ext=mime==="image/png"?"png":mime==="image/webp"?"webp":"jpg",path=`layer2/v2/screenshot-backfill/${ctx.job_id}/${ctx.attempt_id}/visual.${ext}`;
  const up=await svc.storage.from(BUCKET).upload(path,bytes,{contentType:mime,upsert:false});if(up.error)throw new Error("screenshot upload failed: "+up.error.message);
  const ev=await rpc(svc,"layer2_evidence_capture",{p_source_id:ctx.source_id,p_job_id:ctx.job_id,p_evidence_type:"layer2_screenshot",p_source_url:ctx.source_url,p_storage_path:path,p_content_hash:digest,p_mime_type:mime,p_profile_version_id:ctx.profile_version_id,p_group_key:await hash(new TextEncoder().encode(`${evidenceId}|screenshot-backfill|${digest}`)),p_retention_class:"standard_365",p_retain_until:null,p_metadata:{layer:2,worker_version:VERSION,provider_key:"firecrawl",attempt_id:ctx.attempt_id,source_evidence_id:evidenceId,screenshot_origin:"firecrawl_backfill",visual_evidence:true,canonical_mutation_authorised:false,search_mutation_authorised:false,publication_mutation_authorised:false}});
  await rpc(svc,"layer2_screenshot_backfill_attach",{p_attempt_id:ctx.attempt_id,p_screenshot_evidence_id:ev.evidence_id,p_metrics:{screenshot_backfill_worker:VERSION,screenshot_evidence_id:ev.evidence_id,screenshot_bytes:bytes.length,screenshot_mime:mime}});
  return J(200,{ok:true,status:"captured",evidence_id:evidenceId,screenshot_evidence_id:ev.evidence_id,mime_type:mime,bytes:bytes.length,worker_version:VERSION,canonical_mutation_authorised:false,search_mutation_authorised:false,publication_mutation_authorised:false});
 }catch(e:any){return J(500,{ok:false,error:String(e?.message||e),worker_version:VERSION})}
});