import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
function headers(req:Request){const o=req.headers.get('origin')||'';return {'access-control-allow-origin':o===ORIGIN||o.startsWith('http://localhost')?o:ORIGIN,'access-control-allow-headers':'authorization, x-client-info, apikey, content-type','access-control-allow-methods':'POST, OPTIONS','content-type':'application/json','cache-control':'no-store','vary':'origin'}}
function reply(req:Request,status:number,body:unknown){return new Response(JSON.stringify(body),{status,headers:headers(req)})}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS') return new Response(null,{status:204,headers:headers(req)});
  if(req.method!=='POST') return reply(req,405,{error:'method_not_allowed'});
  const auth=req.headers.get('authorization')||'';
  if(!auth.toLowerCase().startsWith('bearer ')) return reply(req,401,{error:'authentication_required'});
  const url=Deno.env.get('SUPABASE_URL');
  const anon=Deno.env.get('SUPABASE_ANON_KEY');
  const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||(()=>{try{return JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||''}catch{return''}})();
  if(!url||!anon||!service) return reply(req,500,{error:'service_configuration_error'});
  const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
  const{data:ctx,error:ctxErr}=await user.rpc('admin_read',{p_operation:'context',p_args:{}});
  if(ctxErr||!ctx?.authenticated) return reply(req,401,{error:'authentication_required'});
  if(Number(ctx?.role_rank||0)<6) return reply(req,403,{error:'platform_admin_role_required'});
  let body:any;try{body=await req.json()}catch{return reply(req,400,{error:'invalid_json'})}
  const action=String(body?.action||'');
  const profileId=String(body?.profile_id||'');
  if(!profileId) return reply(req,400,{error:'profile_id_required'});
  const svc=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});

  if(action==='set_credential'){
    const secret=String(body?.credential||'').trim();
    const reason=String(body?.reason||'').trim();
    if(secret.length<20) return reply(req,400,{error:'provider_credential_required'});
    if(reason.length<4) return reply(req,400,{error:'reason_required'});
    const{data,error}=await svc.rpc('layer3_provider_credential_set_service',{p_actor:String(ctx.user_id),p_profile_id:profileId,p_secret:secret,p_reason:reason});
    if(error) return reply(req,error.code==='42501'?403:400,{error:error.message});
    return reply(req,200,data||{ok:true,credential_configured:true});
  }

  if(action==='verify_credential'){
    const{data:profiles,error:profilesError}=await user.rpc('layer3_model_profiles_admin');
    if(profilesError) return reply(req,400,{error:profilesError.message});
    const profile=(Array.isArray(profiles)?profiles:[]).find((p:any)=>String(p.id)===profileId);
    if(!profile) return reply(req,404,{error:'profile_not_found'});
    const{data:key,error:keyError}=await svc.rpc('layer3_provider_credential_resolve_service',{p_profile_id:profileId});
    if(keyError||!key) return reply(req,409,{error:'provider_credential_not_configured'});
    let ok=false,providerModel:string|null=null,message='',externalCallCount=0,inputTokens:number|null=null,outputTokens:number|null=null,estimatedCostUsd:number|null=null,latencyMs:number|null=null;
    const callStarted=performance.now();
    try{
      const controller=new AbortController();
      const timer=setTimeout(()=>controller.abort(),Math.min(Math.max(Number(profile.timeout_ms||30000),5000),30000));
      externalCallCount=1;
      const res=await fetch(`${String(profile.base_url).replace(/\/$/,'')}/chat/completions`,{
        method:'POST',signal:controller.signal,
        headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json','HTTP-Referer':'https://coursefinder.app','X-Title':'CourseFinder Layer 3 Credential Verification'},
        body:JSON.stringify({model:profile.model_identifier,temperature:0,max_tokens:8,messages:[{role:'user',content:'Reply with exactly OK.'}]})
      });
      clearTimeout(timer);
      const payload=await res.json().catch(()=>({}));
      latencyMs=Math.round(performance.now()-callStarted);
      inputTokens=payload?.usage?.prompt_tokens==null?null:Number(payload.usage.prompt_tokens);
      outputTokens=payload?.usage?.completion_tokens==null?null:Number(payload.usage.completion_tokens);
      estimatedCostUsd=payload?.usage?.cost==null?null:Number(payload.usage.cost);
      ok=res.ok;
      providerModel=payload?.model||profile.model_identifier||null;
      message=ok?'Provider credential verified; full quality benchmark still required.':`Provider returned HTTP ${res.status}`;
      if(!ok&&payload?.error?.message) message+=`: ${String(payload.error.message).slice(0,300)}`;
    }catch(e){latencyMs=Math.round(performance.now()-callStarted);message=e instanceof Error?e.message:String(e)}
    await svc.rpc('layer3_provider_validation_record_service',{p_actor:String(ctx.user_id),p_profile_id:profileId,p_ok:ok,p_provider_model:providerModel,p_message:message,p_external_call_count:externalCallCount,p_input_tokens:inputTokens,p_output_tokens:outputTokens,p_estimated_cost_usd:estimatedCostUsd,p_latency_ms:latencyMs});
    return reply(req,ok?200:409,{ok,profile_id:profileId,provider_model:providerModel,state:ok?'credential_verified_pending_benchmark':'credential_verification_failed',message,usage:{external_call_count:externalCallCount,input_tokens:inputTokens,output_tokens:outputTokens,estimated_cost_usd:estimatedCostUsd,latency_ms:latencyMs}});
  }
  return reply(req,400,{error:'unsupported_action'});
});
