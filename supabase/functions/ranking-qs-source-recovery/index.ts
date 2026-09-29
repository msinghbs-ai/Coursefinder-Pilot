import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
const sha256=async(bytes:Uint8Array)=>{const d=await crypto.subtle.digest("SHA-256",bytes);return[...new Uint8Array(d)].map(x=>x.toString(16).padStart(2,"0")).join("")};
Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json({error:"POST required"},405);
  const body=await req.json().catch(()=>({}));
  const importId=String(body.import_id||""),candidateUrl=String(body.url||"");
  if(!importId||!candidateUrl)return json({error:"import_id and url required"},400);
  let u:URL;try{u=new URL(candidateUrl)}catch{return json({error:"invalid url"},400)}
  if(u.protocol!=="https:"||u.hostname!=="insights.qs.com")return json({error:"only insights.qs.com HTTPS publisher files are allowed"},400);
  const sbUrl=Deno.env.get("SUPABASE_URL")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if(!sbUrl||!service)return json({error:"service configuration missing"},500);
  const svc=createClient(sbUrl,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:ctx,error:ce}=await svc.rpc("svc_ranking_import_recovery_context",{p_import_id:importId});
  if(ce||!ctx?.id)return json({error:"ranking import context unavailable",detail:ce?.message||null},404);
  if(ctx.system_code!=="qs_wur"||!['needs_review','uploaded','validated'].includes(String(ctx.status||'')))return json({error:"import is not an eligible QS recovery target"},409);
  const r=await fetch(u.toString(),{headers:{"User-Agent":"Mozilla/5.0","Accept":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/octet-stream,*/*"}});
  const bytes=new Uint8Array(await r.arrayBuffer());
  const hash=await sha256(bytes);
  const base={ok:r.ok,status:r.status,url:u.toString(),contentType:r.headers.get("content-type"),bytes:bytes.length,sha256:hash,expectedHash:ctx.content_hash,editionYear:ctx.edition_year};
  if(!r.ok)return json(base,422);
  if(hash.toLowerCase()!==String(ctx.content_hash||'').toLowerCase())return json({error:"publisher file hash does not match governed Evidence",...base},409);
  if(body.apply!==true)return json({...base,hashMatch:true});
  const path=`ranking/qs_wur/${ctx.edition_year}/restored-${hash.slice(0,20)}-${crypto.randomUUID()}.xlsx`;
  const up=await svc.storage.from("evidence").upload(path,bytes,{contentType:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",upsert:false,cacheControl:"0"});
  if(up.error)return json({error:`storage upload failed: ${up.error.message}`,...base},422);
  const {data:restored,error:re}=await svc.rpc("svc_ranking_import_storage_restore",{p_import_id:importId,p_storage_path:path,p_content_hash:hash});
  if(re){await svc.storage.from("evidence").remove([path]);return json({error:`restore rpc failed: ${re.message}`,...base},422)}
  const parser=await fetch(`${sbUrl}/functions/v1/ranking-qs-official-etl`,{method:"POST",headers:{authorization:`Bearer ${service}`,apikey:service,"x-cf-layer1-service-key":service,"content-type":"application/json"},body:JSON.stringify({edition_year:Number(ctx.edition_year),mode:"apply",import_id:importId})});
  const parsed=await parser.json().catch(()=>({}));
  if(!parser.ok||parsed?.ok===false)return json({error:parsed?.error||`parser http ${parser.status}`,restored,parser:parsed,...base},422);
  return json({...base,hashMatch:true,restored,parser:parsed,applied:true});
});