import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
function headers(req:Request){const o=req.headers.get('origin')||'';return {'access-control-allow-origin':o===ORIGIN||o.startsWith('http://localhost')?o:ORIGIN,'access-control-allow-headers':'authorization, x-client-info, apikey, content-type','access-control-allow-methods':'POST, OPTIONS','content-type':'application/json','cache-control':'no-store','vary':'origin'}}
function reply(req:Request,status:number,body:unknown){return new Response(JSON.stringify(body),{status,headers:headers(req)})}
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:headers(req)});
 if(req.method!=='POST')return reply(req,405,{error:'method_not_allowed'});
 const auth=req.headers.get('authorization')||'';
 if(!auth.toLowerCase().startsWith('bearer '))return reply(req,401,{error:'authentication_required'});
 const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!anon||!service)return reply(req,500,{error:'service_configuration_error'});
 const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 const{data:ctx,error:ctxErr}=await user.rpc('admin_read',{p_operation:'context',p_args:{}});
 if(ctxErr||!ctx?.authenticated)return reply(req,401,{error:'authentication_required'});
 let body:any;try{body=await req.json()}catch{return reply(req,400,{error:'invalid_json'})}
 const action=String(body?.action||''),rank=Number(ctx?.role_rank||0);
 const svc=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});

 if(action==='profile_options'){
  if(rank<4)return reply(req,403,{error:'pipeline_operator_role_required'});
  const payload=body?.payload||{};
  const{data,error}=await svc.rpc('layer2_provider_profile_options_service',{
   p_actor:String(ctx.user_id),
   p_query:String(payload.query||'').trim()||null,
   p_limit:Math.min(Math.max(Number(payload.limit||10),1),10),
   p_offset:Math.max(Number(payload.offset||0),0)
  });
  if(error)return reply(req,error.code==='42501'?403:400,{error:error.message});
  return reply(req,200,data||{items:[],total:0,limit:10,offset:0,has_more:false});
 }

 if(action==='probe_provider'){
  if(rank<4)return reply(req,403,{error:'pipeline_operator_role_required'});
  const id=String(body?.payload?.id||'');
  if(!id)return reply(req,400,{error:'provider_id_required'});
  const{data:pc,error:pe}=await svc.rpc('layer2_provider_runtime_config',{p_provider_id:id});
  if(pe||!pc)return reply(req,400,{error:pe?.message||'provider_not_found'});
  if(pc.provider_key!=='parsebot')return reply(req,400,{error:'probe_not_supported_for_provider'});
  const base=String(pc.base_url||'https://api.parse.bot').replace(/\/+$/,'');
  let status:number|null=null,probeError:string|null=null;
  const started=Date.now();
  try{
   if(!pc.secret)throw new Error('credential_missing');
   const ctl=new AbortController(),tm=setTimeout(()=>ctl.abort(),Math.min(Math.max(Number(pc.timeout_seconds||30),5),30)*1000);
   let res:Response;
   try{res=await fetch(base+'/dispatch/tasks',{method:'GET',headers:{'X-API-Key':String(pc.secret),'accept':'application/json'},signal:ctl.signal})}finally{clearTimeout(tm)}
   status=res.status;
   if(!res.ok)probeError=res.status===401?'authentication_failed':res.status===404?'parsebot_endpoint_not_found':('http_'+res.status);
  }catch(e:any){probeError=e?.name==='AbortError'?'timeout':String(e?.message||e)}
  const passed=!probeError&&status!==null&&status>=200&&status<300;
  const{error:re}=await svc.rpc('layer2_provider_probe_record_service',{p_provider_id:id,p_status:passed?'passed':'failed',p_http_status:status,p_error:passed?null:probeError});
  if(re)return reply(req,500,{error:'probe_telemetry_write_failed',detail:re.message});
  return reply(req,200,{ok:passed,provider_key:'parsebot',status:passed?'connected':'failed',http_status:status,latency_ms:Date.now()-started,probe_error:probeError,execution_qualified:false,note:'Connectivity validates Parse API base URL and API key only. CourseFinder execution still requires a generated Parse API route (scraper_id + endpoint_name) per source profile.'});
 }

 if(['create_provider','update_provider','set_secret'].includes(action)&&rank<6)return reply(req,403,{error:'platform_admin_role_required'});
 if(action==='upsert_route'&&rank<5)return reply(req,403,{error:'pim_admin_role_required'});
 const{data,error}=await svc.rpc('layer2_provider_control',{p_actor:String(ctx.user_id),p_action:action,p_payload:body?.payload||{}});
 if(error)return reply(req,error.code==='42501'?403:400,{error:error.message});
 return reply(req,200,data||{ok:true});
});
