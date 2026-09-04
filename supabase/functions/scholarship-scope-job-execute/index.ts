import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";
const J=(s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw Error(`${n}: ${error.message}`);return data}
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return J(405,{error:"method_not_allowed"});
 const key=(req.headers.get("x-cf-pilot-key")||"").trim();if(!key)return J(401,{error:"automation_key_required"});
 const sb=Deno.env.get("SUPABASE_URL")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;const svc=createClient(sb,sk,{auth:{persistSession:false}});
 try{if(await rpc(svc,"svc_pilot_automation_authorize",{p_key:key})!==true)return J(401,{error:"invalid_automation_key"})}catch{return J(401,{error:"invalid_automation_key"})}
 const b=await req.json().catch(()=>({})),jobId=String(b.job_id||"");if(!jobId)return J(400,{error:"job_id_required"});
 let ctx:any;try{ctx=await rpc(svc,"scholarship_scope_job_execution_context",{p_job_id:jobId})}catch(e:any){return J(500,{error:"job_context_failed",detail:String(e.message)})}
 if(!ctx?.job_id)return J(404,{error:"job_not_found"});
 if(!ctx?.profile_id||!ctx?.profile_version_id||!ctx?.target_url){await rpc(svc,"scholarship_scope_job_mark",{p_job_id:jobId,p_status:"failed",p_result:{publication_changed:false,canonical_mutation_authorised:false},p_error:"no_executable_first_party_scholarship_catalogue_profile",p_execution:{}});return J(409,{error:"no_executable_first_party_scholarship_catalogue_profile"})}
 const execution={source_id:ctx.source_id,profile_version_id:ctx.profile_version_id,execution_profile_id:ctx.profile_id,execution_profile_key:ctx.profile_key,target_url:ctx.target_url};
 await rpc(svc,"scholarship_scope_job_mark",{p_job_id:jobId,p_status:"running",p_result:null,p_error:null,p_execution:execution});
 try{
  const acq=await fetch(`${sb}/functions/v1/layer2-acquire-v2`,{method:"POST",headers:{"content-type":"application/json","x-cf-pilot-key":key},body:JSON.stringify({profile_id:ctx.profile_id,target_url:ctx.target_url})});
  const at=await acq.text();let ar:any={};try{ar=at?JSON.parse(at):{}}catch{ar={raw:at.slice(0,500)}}
  if(!acq.ok)throw Error(`layer2-acquire-v2 ${acq.status}: ${ar?.error||ar?.detail||at.slice(0,200)}`);
  let fanout:any=null;
  if(ar?.shared_fetch_id){const fr=await fetch(`${sb}/functions/v1/layer2-provider-page-fanout`,{method:"POST",headers:{"content-type":"application/json","x-cf-pilot-key":key},body:JSON.stringify({shared_fetch_id:ar.shared_fetch_id})});const ft=await fr.text();try{fanout=ft?JSON.parse(ft):{}}catch{fanout={raw:ft.slice(0,500)}};if(!fr.ok)fanout={...fanout,error:fanout?.error||`fanout_http_${fr.status}`}}
  const result={acquisition_job_id:ar?.job_id||null,evidence_id:ar?.evidence_id||null,shared_fetch_id:ar?.shared_fetch_id||null,provider_key:ar?.provider_key||null,shared_fetch_reused:ar?.shared_fetch_reused||false,fanout,publication_changed:false,canonical_mutation_authorised:false};
  await rpc(svc,"scholarship_scope_job_mark",{p_job_id:jobId,p_status:"succeeded",p_result:result,p_error:null,p_execution:execution});return J(200,{ok:true,job_id:jobId,...result});
 }catch(e:any){const msg=String(e?.message||e);await rpc(svc,"scholarship_scope_job_mark",{p_job_id:jobId,p_status:"failed",p_result:{publication_changed:false,canonical_mutation_authorised:false},p_error:msg,p_execution:execution});return J(500,{error:"scoped_scholarship_execution_failed",detail:msg})}
});