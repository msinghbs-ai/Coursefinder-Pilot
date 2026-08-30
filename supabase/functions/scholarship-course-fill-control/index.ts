import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";
const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
const H=(r:Request)=>{const o=r.headers.get('origin')||'';return{'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':o===ORIGIN||o.startsWith('http://localhost')?o:ORIGIN,'access-control-allow-headers':'authorization, x-client-info, apikey, content-type','access-control-allow-methods':'POST, OPTIONS','vary':'origin'}};
const J=(r:Request,s:number,b:unknown)=>new Response(JSON.stringify(b),{status:s,headers:H(r)});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:H(req)});
 if(req.method!=='POST')return J(req,405,{error:'method_not_allowed'});
 const ah=req.headers.get('authorization')||'';if(!/^Bearer /i.test(ah))return J(req,401,{error:'authentication_required'});
 const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!anon||!service)return J(req,500,{error:'service_configuration_error'});
 const user=createClient(url,anon,{global:{headers:{Authorization:ah}},auth:{persistSession:false,autoRefreshToken:false}});
 const svc=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const{data:ctx,error:ce}=await user.rpc('admin_read',{p_operation:'context',p_args:{}});
 if(ce||!ctx?.authenticated)return J(req,401,{error:'authentication_required'});
 if(Number(ctx.role_rank||0)<4)return J(req,403,{error:'pipeline_operator_role_required'});
 let b:any;try{b=await req.json()}catch{return J(req,400,{error:'invalid_json'})}
 const action=String(b?.action||'preview');
 if(!['preview','fill','queue_review'].includes(action))return J(req,400,{error:'unsupported_action'});
 const country=String(b?.country_code||'').trim()||null;
 const provider=String(b?.provider_id||'').trim()||null;
 const{data,error}=await svc.rpc('scholarship_course_fill_service',{p_actor:String(ctx.user_id),p_action:action,p_country_code:country,p_provider_id:provider});
 if(error)return J(req,error.code==='42501'?403:400,{error:error.message});
 return J(req,200,data||{ok:true});
});