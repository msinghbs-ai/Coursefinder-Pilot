import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
const LOCAL=new Set(["http://localhost:5173","http://127.0.0.1:5173"]);
const QS_REF="/scrapers/e3ecc5de-f530-478a-b464-867d43099420";
const ARWU_REF="/scrapers/0f6d2cb9-c7eb-4f31-9216-f7be578e9f96";
const QS_EXEC="e3ecc5de-f530-478a-b464-867d43099420";
const ARWU_EXEC="9a025ecd-9ccb-4cf6-a454-be52e290b946";
const json=(req:Request,status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{
 "content-type":"application/json; charset=utf-8","cache-control":"no-store",
 "access-control-allow-origin":LOCAL.has(req.headers.get("origin")||"")?(req.headers.get("origin")||ORIGIN):ORIGIN,
 "access-control-allow-headers":"authorization, x-client-info, apikey, content-type",
 "access-control-allow-methods":"POST, OPTIONS","vary":"origin"
}});
const clean=(v:unknown)=>String(v??"").trim();
const safeRef=(v:string)=>v.startsWith("https://parse.bot")?new URL(v).pathname:v;
async function sha256Hex(bytes:Uint8Array){const hash=await crypto.subtle.digest("SHA-256",bytes);return [...new Uint8Array(hash)].map(b=>b.toString(16).padStart(2,"0")).join("")}
function apiError(payload:any,fallback:string){
 const e=payload?.error;
 if(typeof e==="string"&&e.trim())return e;
 if(e&&typeof e==="object"){
  for(const k of["message","detail","error","kind","status"]){const v=e[k];if(typeof v==="string"&&v.trim())return v}
  try{return JSON.stringify(e)}catch{}
 }
 if(typeof payload?.message==="string"&&payload.message.trim())return payload.message;
 return fallback;
}

Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:{"access-control-allow-origin":ORIGIN,"access-control-allow-headers":"authorization, x-client-info, apikey, content-type","access-control-allow-methods":"POST, OPTIONS"}});
 if(req.method!=="POST")return json(req,405,{error:"method_not_allowed"});
 const auth=req.headers.get("authorization")||"";
 if(!auth.toLowerCase().startsWith("bearer "))return json(req,401,{error:"authentication_required"});
 const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!anon||!serviceKey)return json(req,500,{error:"service_configuration_error"});
 const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:ctx,error:ctxErr}=await user.rpc("admin_read",{p_operation:"context",p_args:{}});
 if(ctxErr||!ctx?.authenticated)return json(req,401,{error:"authentication_required"});
 if(Number(ctx.role_rank||0)<4)return json(req,403,{error:"pipeline_operator_role_required"});
 const actor=clean(ctx.user_id);
 const body=await req.json().catch(()=>({}));
 const systemCode=clean(body.system_code).toLowerCase(),editionYear=Number(body.edition_year),referencePath=safeRef(clean(body.reference_path));
 if(!["qs_wur","arwu"].includes(systemCode))return json(req,400,{error:"url_import_supported_for_qs_arwu_only"});
 if(!Number.isInteger(editionYear)||editionYear<2015||editionYear>2100)return json(req,400,{error:"valid_edition_year_required"});
 const expected=systemCode==="qs_wur"?QS_REF:ARWU_REF;
 if(referencePath!==expected)return json(req,400,{error:"unapproved_parsebot_reference",expected_reference:expected});
 const svc=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:pc,error:pe}=await svc.rpc("layer2_provider_runtime_config_by_key",{p_provider_key:"parsebot"});
 if(pe||!pc?.secret)return json(req,409,{error:"parsebot_credential_unavailable"});
 const key=String(pc.secret),started=Date.now();
 const jobInsert=await svc.schema("pipeline").from("jobs").insert({
   job_type:"ranking_import_acquire",domain:"ranking",status:"running",requested_by:actor,started_at:new Date().toISOString(),
   payload:{action:"acquire",acquisition_mode:"parsebot_api",system_code:systemCode,edition_year:editionYear,reference_path:referencePath}
 }).select("id").single();
 const jobId=jobInsert.data?.id||null;
 try{
  const responses:any[]=[];
  let endpointUrl="",totalRows=0;
  if(systemCode==="qs_wur"){
   let page=0,guard=0;
   do{
    endpointUrl=`https://api.parse.bot/scraper/${QS_EXEC}/get_world_rankings?year=${editionYear}&page=${page}&items_per_page=100`;
    const r=await fetch(endpointUrl,{headers:{"X-API-Key":key,"Accept":"application/json"}});
    const payload=await r.json().catch(()=>({}));
    if(!r.ok||payload?.status!=="success")throw new Error(`QS Parse.bot HTTP ${r.status}: ${apiError(payload,"unexpected response")}`);
    if(String(payload?.data?.edition_year||"")!==String(editionYear))throw new Error("QS edition year mismatch");
    const universities=Array.isArray(payload?.data?.universities)?payload.data.universities:[];
    responses.push(payload);totalRows+=universities.length;
    if(!payload?.data?.has_more)break;
    page++;guard++;
    if(guard>100)throw new Error("QS pagination safety limit exceeded");
   }while(true);
  }else{
   endpointUrl=`https://api.parse.bot/scraper/${ARWU_EXEC}/get_arwu_rankings?year=${editionYear}`;
   const r=await fetch(endpointUrl,{headers:{"X-API-Key":key,"API-Snapshot-Version":"10","Accept":"application/json"}});
   const payload=await r.json().catch(()=>({}));
   if(!r.ok||payload?.status!=="success")throw new Error(`ARWU Parse.bot HTTP ${r.status}: ${apiError(payload,"unexpected response")}`);
   if(String(payload?.data?.year||"")!==String(editionYear))throw new Error("ARWU edition year mismatch");
   responses.push(payload);totalRows=Array.isArray(payload?.data?.rankings)?payload.data.rankings.length:0;
  }
  if(totalRows<=0)throw new Error("Parse.bot returned zero ranking rows");
  const envelope={source:"parsebot",system_code:systemCode,edition_year:editionYear,reference_path:referencePath,
   execution_scraper_id:systemCode==="qs_wur"?QS_EXEC:ARWU_EXEC,endpoint_name:systemCode==="qs_wur"?"get_world_rankings":"get_arwu_rankings",
   api_snapshot_version:systemCode==="arwu"?10:null,fetched_at:new Date().toISOString(),pages:responses.length,total_rows:totalRows,responses};
  const bytes=new TextEncoder().encode(JSON.stringify(envelope)),hash=await sha256Hex(bytes);
  const fileName=`parsebot-${systemCode}-${editionYear}.json`,storagePath=`ranking/${systemCode}/${editionYear}/parsebot-${hash.slice(0,16)}-${crypto.randomUUID()}.json`;
  const up=await svc.storage.from("evidence").upload(storagePath,bytes,{contentType:"application/json",upsert:false,cacheControl:"0"});
  if(up.error)throw new Error("evidence_upload_failed: "+up.error.message);
  const publisherName=systemCode==="qs_wur"?"QS Quacquarelli Symonds":"ShanghaiRanking Consultancy";
  const sourceUrl="https://parse.bot"+referencePath;
  const {data:reg,error:re}=await svc.rpc("svc_ranking_manual_import_register",{
   p_system_code:systemCode,p_edition_year:editionYear,p_publisher_name:publisherName,p_source_url:sourceUrl,
   p_methodology_url:null,p_licensing_note:"Governed Parse.bot ranking acquisition adapter; canonical Apply remains manual.",
   p_revision_note:`Parse.bot established API; ${responses.length} response page(s)`,p_original_filename:fileName,p_mime_type:"application/json",
   p_byte_size:bytes.length,p_content_hash:hash,p_storage_path:storagePath,p_uploaded_by:actor
  });
  if(re){await svc.storage.from("evidence").remove([storagePath]);throw new Error(re.message)}
  if(reg?.duplicate){await svc.storage.from("evidence").remove([storagePath]);}
  if(jobId)await svc.schema("pipeline").from("jobs").update({
    status:"completed",completed_at:new Date().toISOString(),
    payload:{action:"acquire",acquisition_mode:"parsebot_api",system_code:systemCode,edition_year:editionYear,reference_path:referencePath,import_id:reg?.import_id||null},
    result:{ok:true,duplicate:!!reg?.duplicate,import_id:reg?.import_id||null,evidence_id:reg?.evidence_id||null,total_rows:totalRows,pages:responses.length,latency_ms:Date.now()-started}
  }).eq("id",jobId);
  return json(req,200,{ok:true,duplicate:!!reg?.duplicate,import_id:reg?.import_id,evidence_id:reg?.evidence_id||null,job_id:jobId,
   system_code:systemCode,edition_year:editionYear,total_rows:totalRows,pages:responses.length,latency_ms:Date.now()-started,
   reference_path:referencePath,endpoint_name:envelope.endpoint_name,execution_qualified:true});
 }catch(e){
   const message=e instanceof Error?e.message:String(e);
   if(jobId)await svc.schema("pipeline").from("jobs").update({status:"failed",completed_at:new Date().toISOString(),error_text:message,result:{ok:false,error:message}}).eq("id",jobId);
   return json(req,422,{ok:false,error:message,job_id:jobId,system_code:systemCode,edition_year:editionYear})
  }
});
