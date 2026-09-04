import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";
const J=(s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
const sleep=(ms:number)=>new Promise(r=>setTimeout(r,ms));
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw Error(`${n}: ${error.message}`);return data}
async function postJson(url:string,key:string,body:any){const r=await fetch(url,{method:"POST",headers:{"content-type":"application/json","x-cf-pilot-key":key},body:JSON.stringify(body)});const t=await r.text();let j:any={};try{j=t?JSON.parse(t):{}}catch{j={raw:t.slice(0,500)}};if(!r.ok)throw Error(`${url.split('/').pop()} ${r.status}: ${j?.error||j?.detail||t.slice(0,200)}`);return j}
async function extractChain(sb:string,key:string,svc:any,jobId:string,evidenceId:string){
 let ec=await rpc(svc,"scholarship_detail_extraction_context",{p_job_id:jobId,p_evidence_id:evidenceId});
 if(!ec?.eligible)return{skipped:true,reason:ec?.reason||"not_current_detail_ready",classification:ec?.classification||null,candidate_id:ec?.candidate_id||null};
 let normalizedId=String(ec?.existing_normalized_evidence_id||"");
 if(!normalizedId){
   if(!ec?.attempt_id)throw Error("detail evidence has no acquisition attempt_id");
   try{
     const norm=await postJson(`${sb}/functions/v1/layer2-extract-v2`,key,{attempt_id:ec.attempt_id});
     normalizedId=String(norm?.normalized_evidence_id||"");
   }catch(e:any){
     const msg=String(e?.message||e);
     if(!msg.includes("normalized_evidence_upload_failed"))throw e;
     await sleep(350);
     ec=await rpc(svc,"scholarship_detail_extraction_context",{p_job_id:jobId,p_evidence_id:evidenceId});
     normalizedId=String(ec?.existing_normalized_evidence_id||"");
     if(!normalizedId){await sleep(650);ec=await rpc(svc,"scholarship_detail_extraction_context",{p_job_id:jobId,p_evidence_id:evidenceId});normalizedId=String(ec?.existing_normalized_evidence_id||"")}
   }
   if(!normalizedId)throw Error("normalisation collision recovery found no normalized_evidence_id");
 }
 try{
   const scholarship=await postJson(`${sb}/functions/v1/layer2-scholarship-extract`,key,{normalized_evidence_id:normalizedId});
   return{skipped:false,source_evidence_id:evidenceId,normalized_evidence_id:normalizedId,reused_normalized_evidence:Boolean(ec?.existing_normalized_evidence_id),source_record_id:scholarship?.source_record_id||null,candidate:scholarship?.candidate||null,layer3_required:Boolean(scholarship?.layer3_required),layer4_required:Boolean(scholarship?.layer4_required)};
 }catch(e:any){
   const msg=String(e?.message||e);
   if(msg.includes("catalogue_enumeration_required")){
     const marked=await rpc(svc,"scholarship_candidate_mark_catalogue",{p_job_id:jobId,p_reason:"catalogue_enumeration_required"});
     return{skipped:true,reason:"catalogue_enumeration_required",classification:"catalogue_or_filter",candidate_id:marked?.candidate_id||ec?.candidate_id||null,source_evidence_id:evidenceId,normalized_evidence_id:normalizedId,reused_normalized_evidence:Boolean(ec?.existing_normalized_evidence_id)};
   }
   throw e;
 }
}
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return J(405,{error:"method_not_allowed"});
 const key=(req.headers.get("x-cf-pilot-key")||"").trim();if(!key)return J(401,{error:"automation_key_required"});
 const sb=Deno.env.get("SUPABASE_URL")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;const svc=createClient(sb,sk,{auth:{persistSession:false}});
 try{if(await rpc(svc,"svc_pilot_automation_authorize",{p_key:key})!==true)return J(401,{error:"invalid_automation_key"})}catch{return J(401,{error:"invalid_automation_key"})}
 const b=await req.json().catch(()=>({})),jobId=String(b.job_id||"");if(!jobId)return J(400,{error:"job_id_required"});
 let ctx:any;try{ctx=await rpc(svc,"scholarship_scope_job_execution_context",{p_job_id:jobId})}catch(e:any){return J(500,{error:"job_context_failed",detail:String(e.message)})}
 if(!ctx?.job_id)return J(404,{error:"job_not_found"});
 if(!ctx?.profile_id||!ctx?.profile_version_id||!ctx?.target_url){await rpc(svc,"scholarship_scope_job_mark",{p_job_id:jobId,p_status:"failed",p_result:{publication_changed:false,canonical_mutation_authorised:false},p_error:"no_executable_first_party_scholarship_profile",p_execution:{}});return J(409,{error:"no_executable_first_party_scholarship_profile"})}
 const execution={source_id:ctx.source_id,profile_version_id:ctx.profile_version_id,execution_profile_id:ctx.profile_id,execution_profile_key:ctx.profile_key,target_url:ctx.target_url};
 const extractOnly=ctx?.payload?.extract_only===true||String(ctx?.payload?.extract_only||"")==="true";
 const priorEvidence=String(ctx?.payload?.source_evidence_id||ctx?.result?.source_evidence_id||ctx?.result?.evidence_id||"");
 await rpc(svc,"scholarship_scope_job_mark",{p_job_id:jobId,p_status:"running",p_result:null,p_error:null,p_execution:execution});
 try{
   if(extractOnly){
     if(!priorEvidence)throw Error("extract_only job has no source_evidence_id");
     const extraction=await extractChain(sb,key,svc,jobId,priorEvidence);
     const result={source_evidence_id:priorEvidence,extraction,publication_changed:false,canonical_mutation_authorised:false};
     await rpc(svc,"scholarship_scope_job_mark",{p_job_id:jobId,p_status:"succeeded",p_result:result,p_error:null,p_execution:execution});
     return J(200,{ok:true,job_id:jobId,...result});
   }
   const ar=await postJson(`${sb}/functions/v1/layer2-acquire-v2`,key,{profile_id:ctx.profile_id,target_url:ctx.target_url});
   let fanout:any=null;
   if(ar?.shared_fetch_id){try{fanout=await postJson(`${sb}/functions/v1/layer2-provider-page-fanout`,key,{shared_fetch_id:ar.shared_fetch_id})}catch(e:any){fanout={error:String(e.message)}}}
   let extraction:any=null;
   if(String(ctx?.payload?.acquisition_stage||"")==="first_party_detail"&&ar?.evidence_id){extraction=await extractChain(sb,key,svc,jobId,String(ar.evidence_id));}
   const result={acquisition_job_id:ar?.job_id||null,evidence_id:ar?.evidence_id||null,shared_fetch_id:ar?.shared_fetch_id||null,provider_key:ar?.provider_key||null,shared_fetch_reused:ar?.shared_fetch_reused||false,fanout,extraction,publication_changed:false,canonical_mutation_authorised:false};
   await rpc(svc,"scholarship_scope_job_mark",{p_job_id:jobId,p_status:"succeeded",p_result:result,p_error:null,p_execution:execution});
   return J(200,{ok:true,job_id:jobId,...result});
 }catch(e:any){const msg=String(e?.message||e);await rpc(svc,"scholarship_scope_job_mark",{p_job_id:jobId,p_status:"failed",p_result:{publication_changed:false,canonical_mutation_authorised:false},p_error:msg,p_execution:execution});return J(500,{error:"scoped_scholarship_execution_failed",detail:msg})}
});