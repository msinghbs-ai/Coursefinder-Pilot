import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { unzipSync } from "npm:fflate@0.8.2";

const VERSION="layer2-provider-asset-promote-v4.1";
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
 let buf:Uint8Array,mime:string;
 const inlineSvg=String(ctx?.metadata?.inline_svg||"").trim();
 if(inlineSvg){
   if(!/^<svg\b/i.test(inlineSvg)||inlineSvg.length<100||inlineSvg.length>500000)return J(req,422,{error:"inline_svg_invalid"});
   let safeSvg=inlineSvg
     .replace(/<script\b[\s\S]*?<\/script>/gi,"")
     .replace(/<foreignObject\b[\s\S]*?<\/foreignObject>/gi,"")
     .replace(/\s+on[a-z]+\s*=\s*(["'])[\s\S]*?\1/gi,"")
     .replace(/(href|xlink:href)\s*=\s*(["'])\s*javascript:[\s\S]*?\2/gi,'$1="#"');
   buf=new TextEncoder().encode(safeSvg);mime="image/svg+xml";
 }else{
   const target=String(ctx.asset_url),ua={"user-agent":"CourseFinder Provider Asset Validator/3.0"};
   let res:Response|null=null,directError:any=null,fetchProvider="direct-http";
   try{res=await fetch(target,{headers:ua,redirect:"follow"})}catch(e:any){directError=e}
   if(res?.ok){
     buf=new Uint8Array(await res.arrayBuffer());
     mime=(res.headers.get("content-type")||"application/octet-stream").split(";")[0].trim().toLowerCase();
   }else{
     const directStatus=res?.status??null;
     let routes:any[]=[];
     try{routes=await rpc(svc,"layer2_provider_asset_fetch_routes")}catch{}
     for(const route of Array.isArray(routes)?routes:[]){
       try{
         const pc=await rpc(svc,"layer2_provider_runtime_config",{p_provider_id:String(route.id)});
         if(!pc?.enabled||!pc?.base_url||!pc?.secret)continue;
         const u=new URL(String(pc.base_url)),tpl=pc.request_template||{},headers:any={...ua};
         u.searchParams.set(String(tpl.target_url_parameter||"url"),target);
         // Asset-byte mode deliberately omits page-render/static query flags.
         // The target is an already reconciled image URL, not an HTML page.
         if(pc.auth_scheme==="query_param")u.searchParams.set(String(pc.auth_field_name||"apikey"),String(pc.secret));
         else if(pc.auth_scheme==="bearer")headers.authorization="Bearer "+pc.secret;
         else if(pc.auth_scheme==="header")headers[String(pc.auth_field_name||"X-Api-Key")]=pc.secret;
         const rr=await fetch(u.toString(),{headers,redirect:"follow"});
         if(!rr.ok)continue;
         let rm=(rr.headers.get("content-type")||"application/octet-stream").split(";")[0].trim().toLowerCase();
         const rb=new Uint8Array(await rr.arrayBuffer());
         if(rb.byteLength<100)continue;
         if(!["image/svg+xml","image/png","image/jpeg","image/webp"].includes(rm)){
           const head=new TextDecoder().decode(rb.slice(0,800)).trimStart().toLowerCase();
           if(rb[0]===0x89&&rb[1]===0x50&&rb[2]===0x4e&&rb[3]===0x47)rm="image/png";
           else if(rb[0]===0xff&&rb[1]===0xd8&&rb[2]===0xff)rm="image/jpeg";
           else if(rb[0]===0x52&&rb[1]===0x49&&rb[2]===0x46&&rb[3]===0x46&&new TextDecoder().decode(rb.slice(8,12))==="WEBP")rm="image/webp";
           else if(head.startsWith("<svg")||(head.startsWith("<?xml")&&head.includes("<svg")))rm="image/svg+xml";
         }
         const archiveOk=ctx?.metadata?.archive_bundle===true&&(rm==="application/zip"||target.toLowerCase().endsWith(".zip"));
         if(!archiveOk&&!["image/svg+xml","image/png","image/jpeg","image/webp"].includes(rm))continue;
         buf=rb;mime=archiveOk?"application/zip":rm;fetchProvider=String(pc.provider_key||route.provider_key||"proxy");break;
       }catch{}
     }
     if(!buf!)return J(req,502,{error:"asset_fetch_http_error",http_status:directStatus,direct_error:String(directError?.message||directError||""),fallback_exhausted:true});
   }
   (ctx as any)._fetch_provider=fetchProvider;
 }
 if((mime==="application/zip"||String(ctx.asset_url).toLowerCase().endsWith(".zip"))&&ctx?.metadata?.archive_bundle===true){
   try{
     const files=unzipSync(buf),entries=Object.entries(files).filter(([name,data]:any)=>data&&data.length>=100&&/\.(svg|png|jpe?g|webp)$/i.test(name));
     const ranked=entries.map(([name,data]:any)=>{
       const n=name.toLowerCase();let score=0;
       if(n.includes("logo"))score+=6;if(n.includes("qut"))score+=5;
       if(/rgb|screen|digital|web/.test(n))score+=2;
       if(/horizontal|2line|2-line|stack/.test(n))score+=1;
       if(/reverse|white|mono|cmyk|eps/.test(n))score-=1;
       return{name,data,score};
     }).sort((a,b)=>b.score-a.score||a.name.localeCompare(b.name));
     if(!ranked.length)return J(req,422,{error:"archive_logo_not_found"});
     const pick=ranked[0];buf=new Uint8Array(pick.data);
     const n=pick.name.toLowerCase();
     mime=n.endsWith(".svg")?"image/svg+xml":n.endsWith(".png")?"image/png":n.endsWith(".webp")?"image/webp":"image/jpeg";
     (ctx as any)._archive_member=pick.name;
   }catch(e:any){return J(req,422,{error:"archive_extract_failed",detail:String(e?.message||e)})}
 }
 if(buf.byteLength<100||buf.byteLength>5_000_000)return J(req,422,{error:"asset_size_invalid",bytes:buf.byteLength});
 if(!["image/svg+xml","image/png","image/jpeg","image/webp"].includes(mime))return J(req,422,{error:"unsupported_asset_mime",mime});
 const digest=Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",buf))).map(x=>x.toString(16).padStart(2,"0")).join("");
 const storagePath=`providers/${ctx.provider_id}/logo/${digest}.${ext(mime,String(ctx.asset_url))}`;
 const up=await svc.storage.from(BUCKET).upload(storagePath,buf,{contentType:mime,upsert:true,cacheControl:"31536000"});
 if(up.error)return J(req,500,{error:"asset_storage_failed",detail:up.error.message});
 let applied:any;try{applied=await rpc(svc,"layer2_provider_asset_promote_apply",{p_candidate_id:cid,p_storage_path:storagePath,p_mime_type:mime,p_content_hash:digest,p_width:null,p_height:null})}catch(e:any){return J(req,500,{error:"promotion_apply_failed",detail:String(e.message)})}
 return J(req,200,{ok:true,worker_version:VERSION,candidate_id:cid,provider_id:ctx.provider_id,bytes:buf.byteLength,mime_type:mime,content_hash:digest,storage_path:storagePath,fetch_provider:ctx._fetch_provider||"inline-evidence",archive_member:ctx._archive_member||null,applied});
});