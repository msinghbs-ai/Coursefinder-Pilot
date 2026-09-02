import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION="layer2-provider-asset-promote-v1";
const BUCKET="provider-assets";
const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
const H=(r:Request)=>({"content-type":"application/json","cache-control":"no-store","access-control-allow-origin":r.headers.get("origin")===ORIGIN?ORIGIN:ORIGIN,"access-control-allow-headers":"authorization,content-type,x-cf-pilot-key","access-control-allow-methods":"POST,OPTIONS"});
const J=(r:Request,s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:H(r)});
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw Error(n+": "+error.message);return data}
async function auth(req:Request,svc:any,sb:string,anon:string){
 const key=(req.headers.get("x-cf-pilot-key")||"").trim();
 if(key){if(await rpc(svc,"svc_pilot_automation_authorize",{p_key:key})!==true)throw Error("invalid_pilot_automation_key");return}
 const ah=req.headers.get("authorization")||"";if(!/^Bearer /i.test(ah))throw Error("authentication_required");
 const u=createClient(sb,anon,{global:{headers:{Authorization:ah}},auth:{persistSession:false}});
 const{data:ctx,error}=await u.rpc("admin_read",{p_operation:"context",p_args:{}});
 if(error||!ctx?.authenticated)throw Error("authentication_required");if(Number(ctx.role_rank||0)<4)throw Error("pipeline_operator_role_required");
}
function ext(mime:string,url:string){if(mime.includes("svg"))return"svg";if(mime.includes("png"))return"png";if(mime.includes("jpeg")||mime.includes("jpg"))return"jpg";if(mime.includes("webp"))return"webp";const m=url.match(/\.([a-z0-9]{2,5})(?:\?|$)/i);return m?m[1].toLowerCase():"bin"}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:H(req)});if(req.method!=="POST")return J(req,405,{error:"method_not_allowed"});
 const sb=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
 const svc=createClient(sb,sk,{auth:{persistSession:false}});
 try{await auth(req,svc,sb,anon)}catch(e:any){return J(req,String(e.message).includes("role")?403:401,{error:String(e.message)})}
 const b=await req.json().catch(()=>({})),cid=String(b.candidate_id||"");if(!cid)return J(req,400,{error:"candidate_id_required"});
 let ctx:any;try{ctx=await rpc(svc,"layer2_provider_asset_promotion_context",{p_candidate_id:cid})}catch(e:any){return J(req,500,{error:"candidate_context_failed",detail:String(e.message)})}
 if(!ctx?.candidate_id)return J(req,404,{error:"candidate_not_found"});
 if(ctx.candidate_status!=="accepted"||Number(ctx.confidence||0)<0.90)return J(req,409,{error:"candidate_not_approved_for_promotion",confidence:ctx.confidence,status:ctx.candidate_status});
 let res:Response;try{res=await fetch(String(ctx.asset_url),{headers:{"user-agent":"CourseFinder Provider Asset Validator/1.0"},redirect:"follow"})}catch(e:any){return J(req,502,{error:"asset_fetch_failed",detail:String(e.message)})}
 if(!res.ok)return J(req,502,{error:"asset_fetch_http_error",http_status:res.status});
 const buf=new Uint8Array(await res.arrayBuffer());if(buf.byteLength<100||buf.byteLength>5_000_000)return J(req,422,{error:"asset_size_invalid",bytes:buf.byteLength});
 const mime=(res.headers.get("content-type")||"application/octet-stream").split(";")[0].trim().toLowerCase();
 if(!["image/svg+xml","image/png","image/jpeg","image/webp"].includes(mime))return J(req,422,{error:"unsupported_asset_mime",mime});
 const digest=Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",buf))).map(x=>x.toString(16).padStart(2,"0")).join("");
 const storagePath=`providers/${ctx.provider_id}/logo/${digest}.${ext(mime,String(ctx.asset_url))}`;
 const up=await svc.storage.from(BUCKET).upload(storagePath,buf,{contentType:mime,upsert:true,cacheControl:"31536000"});
 if(up.error)return J(req,500,{error:"asset_storage_failed",detail:up.error.message});
 let applied:any;try{applied=await rpc(svc,"layer2_provider_asset_promote_apply",{p_candidate_id:cid,p_storage_path:storagePath,p_mime_type:mime,p_content_hash:digest,p_width:null,p_height:null})}catch(e:any){return J(req,500,{error:"promotion_apply_failed",detail:String(e.message)})}
 return J(req,200,{ok:true,worker_version:VERSION,candidate_id:cid,provider_id:ctx.provider_id,bytes:buf.byteLength,mime_type:mime,content_hash:digest,storage_path:storagePath,applied});
});