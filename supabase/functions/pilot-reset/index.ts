import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const VERSION="pilot-reset-v1.0.0";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});if(req.method!=="POST")return json({error:"POST required"},405);
 const url=Deno.env.get("SUPABASE_URL")!,key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,pub=Deno.env.get("SUPABASE_ANON_KEY")||Deno.env.get("SUPABASE_PUBLISHABLE_KEY")||"";const service=createClient(url,key,{auth:{persistSession:false}});
 try{
  const token=(req.headers.get("authorization")||"").replace(/^Bearer\s+/i,"");if(!token)throw new Error("authentication required");const userClient=createClient(url,pub||key,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false}});const {data:{user},error:ue}=await userClient.auth.getUser(token);if(ue||!user)throw new Error("invalid user session");const {data:allowed,error:ae}=await service.rpc("svc_layer1_authorize_platform_admin",{p_user_id:user.id});if(ae)throw new Error(ae.message);if(!allowed)throw new Error("platform_admin required");
  const body=await req.json().catch(()=>({}));const confirmation=String(body.confirm||"").trim().toUpperCase();if(!["RESET DATABASE","RESET AU UAT"].includes(confirmation))return json({error:"confirmation required: RESET DATABASE"},400);
  const {data:seedBefore}=await service.rpc("svc_layer1_seed_status");
  const {data:stats,error}=await service.rpc("svc_layer1_reset_database");if(error)throw new Error(error.message);
  const empty=await service.storage.emptyBucket("evidence");if(empty.error)throw new Error(`evidence bucket cleanup: ${empty.error.message}`);
  const {data:seedAfter}=await service.rpc("svc_layer1_seed_status");
  return json({ok:true,version:VERSION,...stats,evidence_objects:0,seed_preserved:seedAfter||[],seed_before:seedBefore||[]});
 }catch(e){console.error(e);return json({error:String(e),version:VERSION},500);}
});