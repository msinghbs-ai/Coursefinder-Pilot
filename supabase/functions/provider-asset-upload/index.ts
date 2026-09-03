import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "access-control-allow-origin":"*",
  "access-control-allow-headers":"authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods":"POST, OPTIONS",
  "cache-control":"no-store",
  "referrer-policy":"no-referrer",
};
const jsonHeaders={...cors,"content-type":"application/json; charset=utf-8"};
const uuidRe=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:jsonHeaders});
const allowed=new Set(["image/svg+xml","image/png","image/jpeg","image/webp"]);
const ext=(mime:string)=>mime==="image/svg+xml"?"svg":mime==="image/png"?"png":mime==="image/webp"?"webp":"jpg";

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
  if(req.method!=="POST")return reply(405,{error:"method_not_allowed"});
  const authHeader=req.headers.get("authorization")||"";
  if(!authHeader.toLowerCase().startsWith("bearer "))return reply(401,{error:"authentication_required"});

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
  if(Number(context?.role_rank||0)<5)return reply(403,{error:"pim_operator_role_required"});

  let form:FormData;
  try{form=await req.formData()}catch{return reply(400,{error:"multipart_form_required"})}
  const providerId=String(form.get("provider_id")||"").trim();
  const file=form.get("file");
  if(!uuidRe.test(providerId))return reply(400,{error:"invalid_provider_id"});
  if(!(file instanceof File))return reply(400,{error:"logo_file_required"});
  if(file.size<100||file.size>5_000_000)return reply(422,{error:"asset_size_invalid",bytes:file.size,max_bytes:5_000_000});
  const mime=String(file.type||"").split(";")[0].trim().toLowerCase();
  if(!allowed.has(mime))return reply(422,{error:"unsupported_asset_mime",mime});

  const bytes=new Uint8Array(await file.arrayBuffer());
  const digest=Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",bytes))).map(x=>x.toString(16).padStart(2,"0")).join("");
  const storagePath=`providers/${providerId}/logo/manual/${digest}.${ext(mime)}`;
  const serviceClient=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});

  const upload=await serviceClient.storage.from("provider-assets").upload(storagePath,bytes,{contentType:mime,upsert:true,cacheControl:"31536000"});
  if(upload.error)return reply(500,{error:"asset_storage_failed",detail:upload.error.message});

  const {data:applied,error:applyError}=await serviceClient.rpc("svc_provider_asset_manual_upload_apply",{
    p_provider_id:providerId,
    p_storage_path:storagePath,
    p_mime_type:mime,
    p_content_hash:digest,
    p_actor_id:context.user_id,
  });
  if(applyError){
    await serviceClient.storage.from("provider-assets").remove([storagePath]);
    return reply(500,{error:"provider_asset_apply_failed",detail:applyError.message});
  }

  const {data:signed,error:signedError}=await serviceClient.storage.from("provider-assets").createSignedUrl(storagePath,600);
  return reply(200,{
    ok:true,
    provider_id:providerId,
    provider_asset_id:applied?.provider_asset_id,
    content_hash:digest,
    mime_type:mime,
    bytes:file.size,
    storage_path:storagePath,
    expires_in:600,
    url:!signedError?signed?.signedUrl:null,
  });
});
