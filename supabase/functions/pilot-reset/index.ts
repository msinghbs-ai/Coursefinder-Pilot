import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const VERSION="pilot-reset-v1.1.0-security-release";
const WORKER_ORIGIN="https://coursefinder-pilot.techm.workers.dev";
const LOCAL_ORIGINS=new Set(["http://localhost:5173","http://127.0.0.1:5173"]);
function cors(req:Request){const origin=req.headers.get("origin")||"";const allow=origin===WORKER_ORIGIN||LOCAL_ORIGINS.has(origin)?origin:WORKER_ORIGIN;return{"Access-Control-Allow-Origin":allow,"Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Cache-Control":"no-store","Vary":"Origin"};}
const json=(req:Request,b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors(req),"Content-Type":"application/json"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors(req)});
 if(req.method!=="POST")return json(req,{error:"method_not_allowed"},405);
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),pub=Deno.env.get("SUPABASE_ANON_KEY")||Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
 if(!url||!key||!pub)return json(req,{error:"service_configuration_error",version:VERSION},500);
 const token=(req.headers.get("authorization")||"").replace(/^Bearer\s+/i,"");
 if(!token)return json(req,{error:"authentication_required",version:VERSION},401);
 const service=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 const userClient=createClient(url,pub,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 try{
  const {data:{user},error:ue}=await userClient.auth.getUser(token);if(ue||!user)return json(req,{error:"invalid_user_session",version:VERSION},401);
  const {data:allowed,error:ae}=await service.rpc("svc_layer1_authorize_platform_admin",{p_user_id:user.id});if(ae)throw new Error(ae.message);if(!allowed)return json(req,{error:"platform_admin_required",version:VERSION},403);
  const body=await req.json().catch(()=>({}));if(String(body?.confirm||"").trim().toUpperCase()!=="RESET DATABASE")return json(req,{error:"confirmation_required",required:"RESET DATABASE",version:VERSION},400);
  const {data:seedBefore}=await service.rpc("svc_layer1_seed_status");
  const {data:stats,error}=await service.rpc("svc_layer1_reset_database");if(error)throw new Error(error.message);
  const empty=await service.storage.emptyBucket("evidence");if(empty.error)throw new Error(`evidence bucket cleanup: ${empty.error.message}`);
  const {data:seedAfter}=await service.rpc("svc_layer1_seed_status");
  return json(req,{ok:true,version:VERSION,...stats,evidence_objects:0,seed_preserved:seedAfter||[],seed_before:seedBefore||[]});
 }catch(e){console.error("pilot-reset failed",e instanceof Error?e.message:String(e));return json(req,{error:"reset_failed",version:VERSION},500);}
});