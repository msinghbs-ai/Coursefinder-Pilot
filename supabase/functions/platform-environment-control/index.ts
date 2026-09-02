import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
function headers(req:Request){const o=req.headers.get("origin")||"";return{"access-control-allow-origin":o===ORIGIN||o.startsWith("http://localhost")?o:ORIGIN,"access-control-allow-headers":"authorization, x-client-info, apikey, content-type","access-control-allow-methods":"POST, OPTIONS","content-type":"application/json","cache-control":"no-store","vary":"origin"}}
function reply(req:Request,status:number,body:any){return new Response(JSON.stringify(body),{status,headers:headers(req)})}

Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:headers(req)});
 if(req.method!=="POST")return reply(req,405,{error:"method_not_allowed"});
 const auth=req.headers.get("authorization")||"";
 if(!auth.toLowerCase().startsWith("bearer "))return reply(req,401,{error:"authentication_required"});
 const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||(()=>{try{return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}").default||""}catch{return""}})();
 if(!url||!anon||!secret)return reply(req,500,{error:"service_configuration_error"});
 const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 const{data:ctx,error:ce}=await user.rpc("admin_read",{p_operation:"context",p_args:{}});
 if(ce||!ctx?.authenticated)return reply(req,401,{error:"authentication_required"});
 if(Number(ctx.role_rank||0)<6)return reply(req,403,{error:"platform_admin_role_required"});
 const svc=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 let body:any={};try{body=await req.json()}catch{return reply(req,400,{error:"invalid_json"})}
 const action=String(body?.action||"read");
 if(action==="read"){
   const{data,error}=await svc.rpc("platform_environment_read_service");
   if(error)return reply(req,400,{error:error.message});
   return reply(req,200,data||{});
 }
 const{data,error}=await svc.rpc("platform_environment_control_service",{p_actor:String(ctx.user_id),p_action:action,p_payload:body?.payload||{}});
 if(error)return reply(req,error.code==="42501"?403:400,{error:error.message});
 return reply(req,200,data||{ok:true});
});