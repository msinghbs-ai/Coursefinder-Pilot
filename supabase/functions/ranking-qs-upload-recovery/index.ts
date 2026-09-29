import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
const TARGET_IMPORT="7ac94cf0-aff1-4f1a-b0a6-347563353049";
const EXPECTED_HASH="f4d09f8099d676f270afa4f83aa23a073e99f31c0cc4d61da4884a20d554d706";
const EXPECTED_BYTES=311633;
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
const sha256=async(bytes:Uint8Array)=>{const d=await crypto.subtle.digest("SHA-256",bytes);return[...new Uint8Array(d)].map(x=>x.toString(16).padStart(2,"0")).join("")};
const err=(e:unknown)=>e instanceof Error?e.message:String(e||"unknown error");
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return json({error:"POST required"},405);
 const importId=req.headers.get("x-cf-import-id")||"";
 if(importId!==TARGET_IMPORT)return json({error:"invalid recovery target"},400);
 const sbUrl=Deno.env.get("SUPABASE_URL")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
 if(!sbUrl||!service)return json({error:"service configuration missing"},500);
 const svc=createClient(sbUrl,service,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
   const {data:ctx,error:ce}=await svc.rpc("svc_ranking_import_recovery_context",{p_import_id:importId});
   if(ce||!ctx?.id)throw new Error(`ranking import context unavailable: ${ce?.message||"missing"}`);
   if(ctx.system_code!=="qs_wur"||Number(ctx.edition_year)!==2027)throw new Error("target is not QS 2027");
   if(String(ctx.content_hash||"").toLowerCase()!==EXPECTED_HASH)throw new Error("governed Evidence hash differs from authorised recovery target");
   const bytes=new Uint8Array(await req.arrayBuffer());
   if(bytes.length!==EXPECTED_BYTES)throw new Error(`unexpected byte size ${bytes.length}`);
   const hash=await sha256(bytes);
   if(hash!==EXPECTED_HASH)throw new Error(`uploaded file hash mismatch: ${hash}`);
   const path=`ranking/qs_wur/2027/restored-${hash.slice(0,20)}-${crypto.randomUUID()}.xlsx`;
   const up=await svc.storage.from("evidence").upload(path,bytes,{contentType:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",upsert:false,cacheControl:"0"});
   if(up.error)throw new Error(`storage upload failed: ${up.error.message}`);
   const {data:restored,error:re}=await svc.rpc("svc_ranking_import_storage_restore",{p_import_id:importId,p_storage_path:path,p_content_hash:hash});
   if(re){await svc.storage.from("evidence").remove([path]);throw new Error(`restore RPC failed: ${re.message}`)}
   const parser=await fetch(`${sbUrl}/functions/v1/ranking-qs-official-etl`,{method:"POST",headers:{authorization:`Bearer ${service}`,apikey:service,"x-cf-layer1-service-key":service,"content-type":"application/json"},body:JSON.stringify({edition_year:2027,mode:"apply",import_id:importId})});
   const parsed=await parser.json().catch(()=>({}));
   if(!parser.ok||parsed?.ok===false)throw new Error(`parser failed: ${parsed?.error||parser.status}`);
   return json({ok:true,import_id:importId,hash,bytes:bytes.length,storage_path:path,restored,parser:parsed});
 }catch(e){return json({ok:false,error:err(e)},422)}
});