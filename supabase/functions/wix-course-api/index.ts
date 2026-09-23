import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type Json = Record<string, unknown>;
const CONTRACT_VERSION = "wix-cache-v1";

// CF-CHG-20260915-247 WP3c: this function previously existed only in the live
// Pilot project (v3). It is now in source control. sync_courses,
// reference_bundle and lookup are unchanged. search and scholarships are
// additive and read service-only website functions; no Zoho function changes.
const ACTIONS = ["sync_courses","reference_bundle","lookup","search","scholarships"];

const cleanText = (v: unknown) => typeof v === "string" ? v.trim() : "";
const integer = (v: unknown, fallback:number) => { const n=Number(v); return Number.isInteger(n)?n:fallback; };
const json = (status:number, body:unknown, requestId:string, extra:Record<string,string>={}) => new Response(JSON.stringify(body), {status, headers:{"content-type":"application/json","cache-control":"no-store","x-request-id":requestId,...extra}});
const err = (status:number, code:string, requestId:string, extra:Record<string,string>={}) => json(status,{error:{code},request_id:requestId},requestId,extra);
function token(req:Request, body:Json){
  const a=req.headers.get("authorization")||"";
  const bearer=a.match(/^Bearer\s+(.+)$/i)?.[1]?.trim()||"";
  if(bearer) return bearer;
  const direct=(req.headers.get("x-cf-token")||"").trim();
  if(direct) return direct;
  return cleanText(body.integration_token);
}
async function sha256Hex(value:string){ const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value)); return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,"0")).join(""); }

Deno.serve(async (req:Request)=>{
  const requestId=crypto.randomUUID();
  if(req.method!=="POST") return err(405,"METHOD_NOT_ALLOWED",requestId);
  let body:Json; try{body=await req.json();}catch{return err(400,"INVALID_JSON",requestId);}

  const url=Deno.env.get("SUPABASE_URL"); const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!service) return err(503,"SERVICE_UNAVAILABLE",requestId);
  const svc=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});

  const supplied=token(req,body);
  if(!supplied || supplied.length>512) return err(401,"AUTHENTICATION_REQUIRED",requestId);
  const tokenHash=await sha256Hex(supplied);
  const {data:authOk,error:authError}=await svc.rpc("website_edge_auth_v1",{p_token_sha256:tokenHash});
  if(authError || authOk!==true) return err(401,"AUTHENTICATION_REQUIRED",requestId);
  delete body.integration_token;

  const action=cleanText(body.action);
  if(!ACTIONS.includes(action)) return err(400,"INVALID_ACTION",requestId);

  const {data:rate,error:rateError}=await svc.rpc("zoho_edge_rate_check_v1",{p_identity:"coursefinder_wix_pilot_v1",p_resource:action,p_limit:60,p_window_seconds:60});
  if(rateError) return err(503,"SERVICE_UNAVAILABLE",requestId);
  const rs=(rate&&typeof rate==="object")?rate as Record<string,unknown>:{};
  if(rs.allowed!==true){ const retry=Math.max(Number(rs.retry_after_seconds)||1,1); return err(429,"RATE_LIMITED",requestId,{"retry-after":String(retry)}); }

  let data:any=null,error:any=null;
  if(action==="reference_bundle"){
    ({data,error}=await svc.rpc("zoho_edge_reference_bundle_v1"));
  } else if(action==="lookup"){
    const identifier=cleanText(body.identifier); if(!identifier) return err(400,"INVALID_INPUT",requestId);
    ({data,error}=await svc.rpc("zoho_edge_course_lookup_v1",{p_identifier:identifier}));
  } else if(action==="search"||action==="scholarships"){
    const rawFilters=body.filters;
    if(rawFilters!==undefined && (rawFilters===null||typeof rawFilters!=="object"||Array.isArray(rawFilters))) return err(400,"INVALID_INPUT",requestId);
    const page=integer(body.page,1), pageSize=integer(body.page_size,20);
    if(page<1||pageSize<1||pageSize>50) return err(400,"INVALID_INPUT",requestId);
    const fn=action==="search"?"website_edge_course_search_v1":"website_edge_scholarship_search_v1";
    ({data,error}=await svc.rpc(fn,{p_filters:(rawFilters as Json)||{},p_page:page,p_page_size:pageSize}));
    if(error && (error.code==="22023"||String(error.message||"").includes("INVALID_INPUT"))) return err(400,"INVALID_INPUT",requestId);
  } else {
    const limit=Math.min(Math.max(integer(body.limit,50),1),50);
    const offset=Math.max(integer(body.offset,0),0);
    const changedSince=cleanText(body.changed_since)||null;
    ({data,error}=await svc.rpc("zoho_edge_course_search_v2",{
      p_query:null,p_country_codes:null,p_provider_ids:null,p_subdivision_codes:null,p_study_level_codes:null,p_primary_field_codes:null,p_delivery_modes:null,
      p_has_scholarship:null,p_has_intake:null,p_has_english:null,p_has_provider_current_tuition:null,p_has_regulatory_tuition:null,p_has_link:null,
      p_intake_years:null,p_intake_labels:null,p_english_test_codes:null,p_min_provider_annual_tuition:null,p_max_provider_annual_tuition:null,
      p_min_regulatory_total_tuition:null,p_max_regulatory_total_tuition:null,p_publication_statuses:null,p_changed_since:changedSince,p_limit:limit,p_offset:offset
    }));
  }
  if(error) return err(503,"SERVICE_UNAVAILABLE",requestId);
  const obj=(data&&typeof data==="object")?data as Record<string,unknown>:{};
  return json(200,{contract_version:CONTRACT_VERSION,source_contract_version:obj.contract_version??null,...obj,request_id:requestId},requestId);
});
