import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";
const J=(s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw Error(`${n}: ${error.message}`);return data}
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return J(405,{error:"method_not_allowed"});
 const sb=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!sb||!anon||!sk)return J(500,{error:"service_configuration_error"});
 const auth=req.headers.get("authorization")||"";if(!/^Bearer /i.test(auth))return J(401,{error:"authentication_required"});
 const user=createClient(sb,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}}),svc=createClient(sb,sk,{auth:{persistSession:false}});
 let ctx:any;try{ctx=await rpc(user,"admin_read",{p_operation:"context",p_args:{}})}catch(e:any){return J(401,{error:"authentication_required",detail:String(e.message)})}
 const rank=Number(ctx?.role_rank||0);if(rank<4)return J(403,{error:"pipeline_operator_role_required"});
 const actor=String(ctx?.user_id||"");if(!actor)return J(403,{error:"actor_context_required"});
 const b=await req.json().catch(()=>({}));const action=String(b.action||"preview").toLowerCase(),scopeType=String(b.scope_type||"country").toLowerCase(),country=String(b.country_code||"AU").toUpperCase(),scopeId=b.scope_id?String(b.scope_id):null;
 if(!["preview","start","reconcile_preview","reconcile_apply"].includes(action))return J(400,{error:"unsupported_action"});if(!["country","university"].includes(scopeType))return J(400,{error:"scope_type_must_be_country_or_university"});if(scopeType==="university"&&!scopeId)return J(400,{error:"university_scope_id_required"});
 if(action==="reconcile_apply"&&rank<5)return J(403,{error:"pim_admin_role_required_for_canonical_reconciliation"});
 const {data:settings,error:se}=await svc.from("scholarship_runtime_settings").select("country_code,enabled,detail_batch_limit,auto_dispatch,catalogue_refresh_hours,detail_refresh_hours,metadata").eq("country_code",country).maybeSingle();
 if(se)return J(500,{error:"settings_read_failed",detail:se.message});const s=settings||{country_code:country,enabled:true,detail_batch_limit:25,auto_dispatch:true,catalogue_refresh_hours:168,detail_refresh_hours:168,metadata:{international_only:true,publication_authorised:false}};
 if(action==="start"&&s.enabled===false)return J(409,{error:"scholarship_runtime_disabled_for_country",country_code:country});
 try{
  if(action.startsWith("reconcile_")){
   const mode=action==="reconcile_apply"?"apply":"preview";
   const reconciliation=await rpc(svc,"reconcile_verified_detail_records",{p_actor:actor,p_action:mode,p_country_code:country,p_provider_id:scopeType==="university"?scopeId:null,p_limit:100});
   return J(200,{ok:true,action,scope_type:scopeType,scope_id:scopeId,country_code:country,reconciliation,publication_changed:false,canonical_mutation_authorised:action==="reconcile_apply",next_step:action==="reconcile_apply"?"Verified individual first-party details were linked or created as unpublished canonical roots. Generic/catalogue fragments remain review-only.":"Read-only reconciliation preview; no canonical Scholarship rows were changed."});
  }
  const catalogue=await rpc(svc,"scholarship_scope_acquisition_service",{p_actor:actor,p_action:action,p_country_code:country,p_scope_type:scopeType,p_scope_id:scopeId});
  const detail=await rpc(svc,"scholarship_international_detail_batch_service",{p_actor:actor,p_action:action,p_country_code:country,p_scope_type:scopeType,p_scope_id:scopeId,p_limit:Number(s.detail_batch_limit||25),p_dispatch:action==="start"?Boolean(s.auto_dispatch):false});
  return J(200,{ok:true,action,scope_type:scopeType,scope_id:scopeId,country_code:country,settings:s,catalogue,detail,publication_changed:false,canonical_mutation_authorised:false,next_step:action==="start"?"Catalogue jobs and currently qualified international detail jobs were started. Re-running the same scope is idempotent and picks up newly enumerated detail candidates.":"Read-only preview only; no jobs or candidate classifications were changed by the preview request."});
 }catch(e:any){return J(500,{error:"scholarship_runtime_control_failed",detail:String(e?.message||e)})}
});