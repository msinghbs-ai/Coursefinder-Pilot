import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type Json = Record<string, unknown>;
const json=(status:number,body:unknown,requestId:string,extra:Record<string,string>={})=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store","x-request-id":requestId,...extra}});
const clean=(v:unknown)=>typeof v==="string"?v.trim():"";
const int=(v:unknown,d:number)=>{const n=Number(v);return Number.isInteger(n)?n:d};
const arr=(v:unknown)=>Array.isArray(v)?v.map(clean).filter(Boolean).slice(0,50):null;
const ints=(v:unknown)=>Array.isArray(v)?v.map(Number).filter(Number.isInteger).slice(0,50):null;
const num=(v:unknown)=>{if(v===null||v===undefined||v==="")return null;const n=Number(v);return Number.isFinite(n)?n:null};
const err=(status:number,code:string,id:string,extra:Record<string,string>={})=>json(status,{error:{code,message:({INVALID_JSON:"Malformed JSON request",INVALID_ACTION:"Unsupported action",INVALID_INPUT:"Invalid request input",AUTHENTICATION_REQUIRED:"Authentication required",RATE_LIMITED:"Rate limited — retry later",NOT_FOUND:"Course not found",SERVICE_UNAVAILABLE:"CourseFinder service unavailable"} as Record<string,string>)[code]||"Request failed"},request_id:id},id,extra);
async function sha256Hex(value:string){const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value));return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,"0")).join("")}

Deno.serve(async(req:Request)=>{
  const requestId=crypto.randomUUID();
  const started=performance.now();
  if(req.method!=="POST") return err(405,"INVALID_ACTION",requestId);
  const url=Deno.env.get("SUPABASE_URL");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!service) return err(503,"SERVICE_UNAVAILABLE",requestId);
  const svc=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  let body:Json; try{body=await req.json()}catch{return err(400,"INVALID_JSON",requestId)}
  const token=clean(req.headers.get("x-cf-token"))||clean(body.integration_token);
  if(!token||token.length>512) return err(401,"AUTHENTICATION_REQUIRED",requestId);
  const {data:authOk,error:authError}=await svc.rpc("website_edge_auth_v1",{p_token_sha256:await sha256Hex(token)});
  if(authError||authOk!==true) return err(401,"AUTHENTICATION_REQUIRED",requestId);
  delete body.integration_token;
  const action=clean(body.action).toLowerCase();
  if(!["search","lookup","provider_options","filter_options","reference_bundle"].includes(action)) return err(400,"INVALID_ACTION",requestId);
  const perActionLimit=action==="reference_bundle"?12:60;
  const {data:rate,error:rateError}=await svc.rpc("website_edge_rate_check_v1",{p_identity:"coursefinder_website_wix_pilot_v1",p_resource:action,p_limit:perActionLimit,p_window_seconds:60});
  if(rateError) return err(503,"SERVICE_UNAVAILABLE",requestId);
  const rs=(rate&&typeof rate==="object")?rate as Record<string,unknown>:{};
  if(rs.allowed!==true){const retry=Math.max(Number(rs.retry_after_seconds)||1,1);return err(429,"RATE_LIMITED",requestId,{"retry-after":String(retry)})}
  try{
    let data:unknown=null; let error:any=null;
    if(action==="search"){
      const limit=Math.min(Math.max(int(body.limit,12),1),50), offset=Math.max(int(body.offset,0),0);
      ({data,error}=await svc.rpc("zoho_edge_course_search_v2",{
        p_query:clean(body.query)||null,
        p_country_codes:arr(body.country_codes),
        p_provider_ids:arr(body.provider_ids),
        p_subdivision_codes:arr(body.subdivision_codes),
        p_study_level_codes:arr(body.study_level_codes),
        p_primary_field_codes:arr(body.primary_field_codes),
        p_delivery_modes:arr(body.delivery_modes),
        p_has_scholarship:typeof body.has_scholarship==="boolean"?body.has_scholarship:null,
        p_has_intake:typeof body.has_intake==="boolean"?body.has_intake:null,
        p_has_english:typeof body.has_english==="boolean"?body.has_english:null,
        p_has_provider_current_tuition:typeof body.has_provider_current_tuition==="boolean"?body.has_provider_current_tuition:null,
        p_has_regulatory_tuition:typeof body.has_regulatory_tuition==="boolean"?body.has_regulatory_tuition:null,
        p_has_link:typeof body.has_link==="boolean"?body.has_link:null,
        p_intake_years:ints(body.intake_years),
        p_intake_labels:arr(body.intake_labels),
        p_english_test_codes:arr(body.english_test_codes),
        p_min_provider_annual_tuition:num(body.min_provider_annual_tuition),
        p_max_provider_annual_tuition:num(body.max_provider_annual_tuition),
        p_min_regulatory_total_tuition:num(body.min_regulatory_total_tuition),
        p_max_regulatory_total_tuition:num(body.max_regulatory_total_tuition),
        p_publication_statuses:arr(body.publication_statuses),
        p_changed_since:null,p_limit:limit,p_offset:offset
      }));
    }else if(action==="lookup"){
      const identifier=clean(body.identifier); if(!identifier||identifier.length>200)return err(400,"INVALID_INPUT",requestId);
      ({data,error}=await svc.schema("api").rpc("website_course_lookup_preview_v1",{p_identifier:identifier}));
    }else if(action==="provider_options"){
      const limit=Math.min(Math.max(int(body.limit,10),1),50),offset=Math.max(int(body.offset,0),0);
      ({data,error}=await svc.rpc("zoho_edge_provider_search_v1",{p_query:clean(body.query)||null,p_country_code:clean(body.country_code)||null,p_changed_since:null,p_limit:limit,p_offset:offset}));
    }else if(action==="filter_options"){
      const kind=clean(body.kind).toLowerCase(); if(!["country","subdivision"].includes(kind))return err(400,"INVALID_INPUT",requestId);
      const limit=Math.min(Math.max(int(body.limit,10),1),50),offset=Math.max(int(body.offset,0),0);
      ({data,error}=await svc.rpc("zoho_edge_filter_options_v1",{p_kind:kind,p_country_code:clean(body.country_code)||null,p_query:clean(body.query)||null,p_limit:limit,p_offset:offset}));
    }else{
      ({data,error}=await svc.rpc("zoho_edge_reference_bundle_v1"));
    }
    if(error){console.error(JSON.stringify({event:"website_course_api_error",request_id:requestId,action,error_code:error?.code||null,elapsed_ms:Math.round(performance.now()-started)}));return err(503,"SERVICE_UNAVAILABLE",requestId)}
    const obj=(data&&typeof data==="object")?data as Record<string,unknown>:{};
    if(action==="lookup" && (!obj.item || obj.error==="NOT_FOUND" || obj.code==="NOT_FOUND")) return err(404,"NOT_FOUND",requestId);
    console.log(JSON.stringify({event:"website_course_api_request",request_id:requestId,action,outcome:"ok",elapsed_ms:Math.round(performance.now()-started)}));
    return json(200,{...obj,contract_version:"website-integration-v3-pilot",boundary:"server-side-pilot-only",publication_authority:"not_granted",request_id:requestId},requestId);
  }catch{return err(503,"SERVICE_UNAVAILABLE",requestId)}
});