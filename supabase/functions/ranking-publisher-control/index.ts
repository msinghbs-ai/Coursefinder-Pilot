import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
const LOCAL=new Set(["http://localhost:5173","http://127.0.0.1:5173"]);
const json=(req:Request,status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{
  "content-type":"application/json; charset=utf-8","cache-control":"no-store",
  "access-control-allow-origin":LOCAL.has(req.headers.get("origin")||"")?(req.headers.get("origin")||ORIGIN):ORIGIN,
  "access-control-allow-headers":"authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods":"POST, OPTIONS","vary":"origin"
}});
const clean=(v:unknown)=>String(v??"").trim();

Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:{"access-control-allow-origin":ORIGIN,"access-control-allow-headers":"authorization, x-client-info, apikey, content-type","access-control-allow-methods":"POST, OPTIONS"}});
 if(req.method!=="POST")return json(req,405,{error:"method_not_allowed"});
 const auth=req.headers.get("authorization")||"";
 if(!auth.toLowerCase().startsWith("bearer "))return json(req,401,{error:"authentication_required"});
 const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!anon||!serviceKey)return json(req,500,{error:"service_configuration_error"});
 const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 const {data:ctx,error:ctxErr}=await user.rpc("admin_read",{p_operation:"context",p_args:{}});
 if(ctxErr||!ctx?.authenticated)return json(req,401,{error:"authentication_required"});
 if(Number(ctx.role_rank||0)<4)return json(req,403,{error:"pipeline_operator_role_required"});
 const actor=clean(ctx.user_id);
 const body=await req.json().catch(()=>({}));
 const action=clean(body.action).toLowerCase(),importId=clean(body.import_id);
 if(!["validate","apply"].includes(action))return json(req,400,{error:"unsupported_action"});
 if(!/^[0-9a-f-]{36}$/i.test(importId))return json(req,400,{error:"valid_import_id_required"});
 const svc=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 const {data:imp,error:impErr}=await svc.rpc("svc_ranking_import_control_context",{p_import_id:importId});
 if(impErr)return json(req,500,{error:"ranking_import_lookup_failed",detail:impErr.message});
 if(!imp?.id)return json(req,404,{error:"ranking_import_not_found"});
 const systemCode=clean(imp.system_code),sourceSystem=systemCode==="the_wur"?"THE":"QS";
 const {data:sources,error:sourceErr}=await svc.schema("pipeline").from("sources").select("id,label,metadata").eq("metadata->>source_system",sourceSystem);
 if(sourceErr)return json(req,500,{error:"ranking_source_lookup_failed",detail:sourceErr.message});
 const exact=(sources||[]).find((s:any)=>Number(s.metadata?.edition_year)===Number(imp.edition_year));
 const family=(sources||[]).find((s:any)=>s.metadata?.multi_year_family===true);
 const source=exact||family||sources?.[0]||null;
 const jobType=action==="apply"?"ranking_import_apply":"ranking_import_validate";
 const {data:jobId,error:jobErr}=await svc.rpc("svc_ranking_job_start",{p_job_type:jobType,p_source_id:source?.id||null,p_requested_by:actor,p_payload:{import_id:imp.id,system_code:systemCode,edition_year:imp.edition_year,original_filename:imp.original_filename,action}});
 if(jobErr)return json(req,500,{error:"ranking_job_create_failed",detail:jobErr.message});
 try{
   const res=await fetch(url+"/functions/v1/ranking-layer1-etl",{method:"POST",headers:{
     "authorization":"Bearer "+serviceKey,"apikey":serviceKey,"x-cf-layer1-service-key":serviceKey,"content-type":"application/json"
   },body:JSON.stringify({system_code:systemCode,edition_year:Number(imp.edition_year),mode:action==="apply"?"apply":"dry_run",source_id:source?.id||""})});
   const out=await res.json().catch(()=>({}));
   if(!res.ok||out?.ok===false||out?.error)throw new Error(out?.error||("ranking-layer1-etl HTTP "+res.status));
   if(action==="validate"){
     const {error:updateErr}=await svc.rpc("svc_ranking_import_validation_update",{
       p_import_id:importId,
       p_status:"validated",
       p_validation_summary:{candidate_observations:out.candidateObservations,unknown_rank_semantics:out.unknownRankSemantics,indicator_cells:out.indicatorCells,reconciliation_preview:out.reconciliationPreview,worker_version:out.workerVersion,validated_at:new Date().toISOString()},
       p_parse_summary:{candidate_observations:out.candidateObservations,filename:out.filename,acquisition_mode:out.acquisitionMode}
     });
     if(updateErr)throw new Error(updateErr.message||"ranking import validation update failed");
   }
   const {error:finishErr}=await svc.rpc("svc_ranking_job_finish",{p_job_id:jobId,p_status:"completed",p_result:out,p_error_text:null});if(finishErr)throw new Error(finishErr.message||"ranking job completion failed");
   return json(req,200,{ok:true,action,job_id:jobId,import_id:importId,system_code:systemCode,edition_year:imp.edition_year,result:out});
 }catch(e){
   const message=e instanceof Error?e.message:String(e);
   await svc.rpc("svc_ranking_job_finish",{p_job_id:jobId,p_status:"failed",p_result:{},p_error_text:message});
   await svc.rpc("svc_ranking_import_validation_update",{p_import_id:importId,p_status:imp.status||"uploaded",p_validation_summary:{error:message,failed_at:new Date().toISOString()},p_parse_summary:{}});
   return json(req,422,{ok:false,error:message,job_id:jobId,import_id:importId});
 }
});