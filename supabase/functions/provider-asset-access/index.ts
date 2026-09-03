import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "access-control-allow-origin":"*",
  "access-control-allow-headers":"authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods":"POST, OPTIONS",
  "cache-control":"private, max-age=300",
  "referrer-policy":"no-referrer",
};
const jsonHeaders={...cors,"content-type":"application/json; charset=utf-8"};
const uuidRe=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:jsonHeaders});

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
  if(req.method!=="POST")return reply(405,{error:"method_not_allowed"});
  const authHeader=req.headers.get("authorization")||"";
  if(!authHeader.toLowerCase().startsWith("bearer "))return reply(401,{error:"authentication_required"});

  let body:{provider_id?:string};
  try{body=await req.json()}catch{return reply(400,{error:"invalid_json"})}
  const providerId=String(body?.provider_id||"").trim();
  if(!uuidRe.test(providerId))return reply(400,{error:"invalid_provider_id"});

  const url=Deno.env.get("SUPABASE_URL");
  const anon=Deno.env.get("SUPABASE_ANON_KEY");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)return reply(500,{error:"service_configuration_error"});

  const userClient=createClient(url,anon,{
    global:{headers:{Authorization:authHeader}},
    auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},
  });
  const {data:context,error:contextError}=await userClient.rpc("admin_read",{p_operation:"context",p_args:{}});
  if(contextError||!context?.authenticated)return reply(401,{error:"authentication_required"});
  if(Number(context?.role_rank||0)<1)return reply(403,{error:"catalogue_reader_role_required"});

  const serviceClient=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const {data:descriptor,error:descriptorError}=await serviceClient.rpc("svc_provider_asset_access_descriptor",{p_provider_id:providerId});
  if(descriptorError)return reply(500,{error:"provider_asset_lookup_failed"});
  if(!descriptor?.provider_asset_id||!descriptor?.storage_path)return reply(404,{error:"provider_logo_not_available"});

  const {data:signed,error:signedError}=await serviceClient.storage.from("provider-assets").createSignedUrl(descriptor.storage_path,600);
  if(signedError||!signed?.signedUrl)return reply(500,{error:"signed_access_failed"});

  return reply(200,{
    provider_id:providerId,
    provider_asset_id:descriptor.provider_asset_id,
    asset_type:descriptor.asset_type,
    mime_type:descriptor.mime_type,
    content_hash:descriptor.content_hash,
    verified_at:descriptor.verified_at,
    expires_in:600,
    url:signed.signedUrl,
  });
});
