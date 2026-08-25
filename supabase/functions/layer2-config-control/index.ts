import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const WORKER_ORIGIN = "https://coursefinder-pilot.techm.workers.dev";
const LOCAL_ORIGINS = new Set(["http://localhost:5173", "http://127.0.0.1:5173"]);
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const STATE_ACTIONS = new Set(["validate", "pause", "resume", "disable", "enable"]);
const POLICY_FIELDS = new Set(["schedule_mode","batch_size","routing_strategy","max_paid_attempts_per_entity","auto_handoff_layer3","stop_on_identity_mismatch"]);

function cors(req: Request) {
  const origin = req.headers.get("origin") || "";
  const allowOrigin = origin === WORKER_ORIGIN || LOCAL_ORIGINS.has(origin) ? origin : WORKER_ORIGIN;
  return {"access-control-allow-origin":allowOrigin,"access-control-allow-headers":"authorization, x-client-info, apikey, content-type","access-control-allow-methods":"POST, OPTIONS","cache-control":"no-store","referrer-policy":"no-referrer","vary":"origin"};
}
function reply(req:Request,status:number,body:unknown){return new Response(JSON.stringify(body),{status,headers:{...cors(req),"content-type":"application/json; charset=utf-8"}})}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors(req)});
  if(req.method!=="POST")return reply(req,405,{error:"method_not_allowed"});
  const authHeader=req.headers.get("authorization")||"";
  if(!authHeader.toLowerCase().startsWith("bearer "))return reply(req,401,{error:"authentication_required"});
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)return reply(req,500,{error:"service_configuration_error"});
  const userClient=createClient(url,anon,{global:{headers:{Authorization:authHeader}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const{data:context,error:contextError}=await userClient.rpc("admin_read",{p_operation:"context",p_args:{}});
  if(contextError||!context?.authenticated)return reply(req,401,{error:"authentication_required"});
  let body:Record<string,unknown>={};try{body=await req.json()}catch{return reply(req,400,{error:"invalid_json"})}
  const action=String(body?.action||"").trim().toLowerCase(),profileId=String(body?.profile_id||"").trim(),actorUserId=String(context?.user_id||""),rank=Number(context?.role_rank||0);
  if(!uuidRe.test(profileId))return reply(req,400,{error:"valid_profile_id_required"});
  if(!uuidRe.test(actorUserId))return reply(req,403,{error:"authorised_user_context_invalid"});
  const serviceClient=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  if(action==="update_policy"){
    if(rank<5)return reply(req,403,{error:"pim_admin_role_required"});
    const rawPatch=body?.patch;
    if(!rawPatch||typeof rawPatch!=="object"||Array.isArray(rawPatch))return reply(req,400,{error:"policy_patch_object_required"});
    const entries=Object.entries(rawPatch as Record<string,unknown>);
    if(!entries.length||entries.some(([k])=>!POLICY_FIELDS.has(k)))return reply(req,400,{error:"unsupported_policy_field"});
    const patch=Object.fromEntries(entries);
    const{data,error}=await serviceClient.rpc("layer2_ops_policy_update",{p_actor:actorUserId,p_profile_id:profileId,p_patch:patch});
    if(error)return reply(req,error.code==="42501"?403:400,{error:error.message||"layer2_ops_policy_update_failed"});
    return reply(req,200,data||{ok:true,profile_id:profileId,action});
  }
  if(action==="create_version"){
    if(rank<5)return reply(req,403,{error:"pim_admin_role_required"});
    const configuration=body?.configuration,changeControlRef=String(body?.change_control_ref||"").trim(),uatRef=String(body?.uat_ref||"").trim()||null;
    if(!configuration||typeof configuration!=="object"||Array.isArray(configuration))return reply(req,400,{error:"configuration_object_required"});
    if(!changeControlRef)return reply(req,400,{error:"change_control_ref_required"});
    const{data,error}=await serviceClient.rpc("layer2_create_profile_version",{p_actor:actorUserId,p_profile_id:profileId,p_configuration:configuration,p_change_control_ref:changeControlRef,p_uat_ref:uatRef});
    if(error)return reply(req,error.code==="42501"?403:400,{error:error.message||"layer2_create_profile_version_failed"});
    return reply(req,200,data||{ok:true,profile_id:profileId,action});
  }
  if(!STATE_ACTIONS.has(action))return reply(req,400,{error:"unsupported_action"});
  if(rank<6)return reply(req,403,{error:"platform_admin_role_required"});
  const{data,error}=await serviceClient.rpc("layer2_config_control",{p_actor:actorUserId,p_action:action,p_profile_id:profileId});
  if(error)return reply(req,error.code==="42501"?403:400,{error:error.message||"layer2_config_control_failed"});
  return reply(req,200,data||{ok:true,profile_id:profileId,action});
});
