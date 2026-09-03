import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";

const VERSION="hotcourses-directory-v1";
const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
const H=(r:Request)=>({"content-type":"application/json","cache-control":"no-store","access-control-allow-origin":r.headers.get("origin")===ORIGIN?ORIGIN:ORIGIN,"access-control-allow-headers":"authorization,content-type,x-cf-pilot-key","access-control-allow-methods":"POST,OPTIONS"});
const J=(r:Request,s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:H(r)});
const uuidRe=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const clean=(s:string)=>String(s||"").replace(/<script\b[\s\S]*?<\/script>/gi," ").replace(/<style\b[\s\S]*?<\/style>/gi," ").replace(/<[^>]+>/g," ").replace(/&amp;/gi,"&").replace(/&nbsp;/gi," ").replace(/&#39;/g,"'").replace(/&quot;/gi,'"').replace(/\s+/g," ").trim();
const attr=(tag:string,n:string)=>{const m=tag.match(new RegExp("\\b"+n+"\\s*=\\s*([\"'])([\\s\\S]*?)\\1","i"));return m?m[2]:""};
const abs=(base:string,u:string)=>{try{return new URL(u,base).toString()}catch{return""}};
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw Error(n+": "+error.message);return data}
async function auth(req:Request,svc:any,sb:string,anon:string){
 const key=(req.headers.get("x-cf-pilot-key")||"").trim();
 if(key){if(await rpc(svc,"svc_pilot_automation_authorize",{p_key:key})!==true)throw Error("invalid_pilot_automation_key");return}
 const ah=req.headers.get("authorization")||"";if(!/^Bearer /i.test(ah))throw Error("authentication_required");
 const u=createClient(sb,anon,{global:{headers:{Authorization:ah}},auth:{persistSession:false}});
 const{data:ctx,error}=await u.rpc("admin_read",{p_operation:"context",p_args:{}});
 if(error||!ctx?.authenticated)throw Error("authentication_required");
 if(Number(ctx.role_rank||0)<4)throw Error("pipeline_operator_role_required");
}
function nameFrom(slug:string,inner:string,anchor:string){
 const candidates=[
   clean((inner.match(/<h[1-6][^>]*>([\s\S]*?)<\/h[1-6]>/i)||[])[1]||""),
   clean(attr(anchor,"title")),
   clean(attr(anchor,"aria-label")),
   clean((inner.match(/<img\b[^>]*\balt\s*=\s*["']([^"']+)["'][^>]*>/i)||[])[1]||""),
 ];
 for(const x of candidates)if(x&&x.length>=3&&!/hotcourses|view|more|favourite/i.test(x))return x;
 return slug.split("-").filter(Boolean).map(x=>x[0]?.toUpperCase()+x.slice(1)).join(" ");
}
function logoFrom(base:string,name:string,block:string){
 const n=name.toLowerCase().replace(/[^a-z0-9]+/g,"");
 let best:{url:string;score:number}|null=null;
 for(const m of block.matchAll(/<img\b[^>]*>/gi)){
   const tag=m[0],alt=clean(attr(tag,"alt")),raw=attr(tag,"data-src")||attr(tag,"data-original")||attr(tag,"data-lazy-src")||attr(tag,"data-cfsrc")||attr(tag,"src")||"";
   if(!raw||/img_px\.gif|placeholder|newheader_logo|newfooter_logo|idp_logo/i.test(raw))continue;
   const s=(alt+" "+raw).toLowerCase(),compact=s.replace(/[^a-z0-9]+/g,"");
   let score=0;
   if(/logo|brand|crest|wordmark/.test(s))score+=4;
   if(n&&compact.includes(n))score+=4;
   if(alt&&n&&alt.toLowerCase().replace(/[^a-z0-9]+/g,"")===n)score+=3;
   if(/subject|banner|flag|comment|avatar|social/.test(s))score-=5;
   const url=abs(base,raw);
   if(url&&(!best||score>best.score))best={url,score};
 }
 return best&&best.score>=4?best.url:null;
}
function parse(html:string,base:string){
 const byId=new Map<string,any>();
 const re=/<a\b[^>]*href\s*=\s*(["'])([^"']*\/school-college-university\/([^\/"'?]+)\/([0-9]+)\/international(?:\.html)?[^"']*)\1[^>]*>([\s\S]*?)<\/a>/gi;
 for(const m of html.matchAll(re)){
   const href=m[2],slug=m[3],id=m[4],inner=m[5],anchor=m[0].slice(0,m[0].indexOf(">")+1);
   if(byId.has(id))continue;
   const name=nameFrom(slug,inner,anchor);
   const idx=m.index??0,near=html.slice(Math.max(0,idx-1200),Math.min(html.length,idx+m[0].length+1800));
   byId.set(id,{directory_id:id,name,institution_url:abs(base,href),logo_url:logoFrom(base,name,inner+" "+near)});
 }
 const pages=new Set<string>();
 for(const m of html.matchAll(/<a\b[^>]*href\s*=\s*(["'])([^"']+)\1[^>]*>([\s\S]*?)<\/a>/gi)){
   const href=m[2],label=clean(m[3]);
   if((/^\d+$/.test(label)||/next/i.test(label))&&/list/i.test(href)){
     const u=abs(base,href);if(u)pages.add(u);
   }
 }
 return{rows:[...byId.values()],pagination_urls:[...pages].slice(0,50)};
}

Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:H(req)});
 if(req.method!=="POST")return J(req,405,{error:"method_not_allowed"});
 const sb=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
 const svc=createClient(sb,sk,{auth:{persistSession:false}});
 try{await auth(req,svc,sb,anon)}catch(e:any){return J(req,String(e.message).includes("role")?403:401,{error:String(e.message)})}
 const b=await req.json().catch(()=>({})),eid=String(b.evidence_id||"");
 if(!uuidRe.test(eid))return J(req,400,{error:"invalid_evidence_id"});
 let d:any;try{d=await rpc(svc,"svc_admin_evidence_access_descriptor",{p_evidence_id:eid})}catch(e:any){return J(req,500,{error:"evidence_lookup_failed",detail:String(e.message)})}
 if(!d?.available||!d?.storage_path)return J(req,404,{error:"evidence_unavailable"});
 const dl=await svc.storage.from("evidence").download(d.storage_path);if(dl.error)return J(req,500,{error:"evidence_download_failed",detail:dl.error.message});
 const bytes=new Uint8Array(await dl.data.arrayBuffer());
 let text=new TextDecoder().decode(bytes),base="https://www.hotcoursesabroad.com/";
 if(String(d.mime_type||"").includes("json")){
   try{const j=JSON.parse(text),x=j?.data||j;text=String(x?.html||x?.markdown||x?.content||text);base=String(x?.metadata?.sourceURL||x?.metadata?.url||base)}catch{}
 }
 const parsed=parse(text,base);
 if(!parsed.rows.length)return J(req,422,{error:"no_directory_rows_parsed",parser_version:VERSION,pagination_urls:parsed.pagination_urls});
 let applied:any;try{applied=await rpc(svc,"layer2_hotcourses_directory_apply",{p_evidence_id:eid,p_rows:parsed.rows})}catch(e:any){return J(req,500,{error:"directory_apply_failed",detail:String(e.message)})}
 return J(req,200,{ok:true,parser_version:VERSION,evidence_id:eid,parsed_rows:parsed.rows.length,logo_urls:parsed.rows.filter((x:any)=>x.logo_url).length,pagination_urls:parsed.pagination_urls,...applied});
});
