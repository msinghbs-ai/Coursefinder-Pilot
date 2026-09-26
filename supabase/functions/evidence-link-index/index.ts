import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";

// Package 7 (Decision 146): evidence link index.
// Reads STORED evidence from Supabase Storage (bucket "evidence") and records the links each page
// contains. It never fetches from the web: evidence is captured once and reused.
const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
const H=()=>({"content-type":"application/json","cache-control":"no-store","access-control-allow-origin":ORIGIN,"access-control-allow-headers":"authorization,content-type,x-cf-pilot-key","access-control-allow-methods":"POST,OPTIONS"});
const J=(s:number,b:unknown)=>new Response(JSON.stringify(b),{status:s,headers:H()});
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw Error(`${n}: ${error.message}`);return data}
async function auth(req:Request,svc:any,sb:string,anon:string){
  const key=(req.headers.get("x-cf-pilot-key")||"").trim();
  if(key){if(await rpc(svc,"svc_pilot_automation_authorize",{p_key:key})!==true)throw Error("invalid_pilot_automation_key");return}
  const ah=req.headers.get("authorization")||"";if(!/^Bearer /i.test(ah))throw Error("authentication_required");
  const u=createClient(sb,anon,{global:{headers:{Authorization:ah}},auth:{persistSession:false}});
  const{data:ctx,error}=await u.rpc("admin_read",{p_operation:"context",p_args:{}});
  if(error||!ctx?.authenticated)throw Error("authentication_required");
  if(Number(ctx.role_rank||0)<4)throw Error("pipeline_operator_role_required");
}

const MAX_LINKS=1500, MAX_BYTES=6_000_000;
const siteOf=(h:string)=>h.toLowerCase().replace(/^www\./,"");
const decode=(s:string)=>s.replace(/&amp;/g,"&").replace(/&quot;/g,'"').replace(/&#39;|&apos;/g,"'").replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&nbsp;/g," ");
const clean=(s:string)=>decode(s.replace(/<[^>]*>/g," ")).replace(/\s+/g," ").trim().slice(0,200);

function resolve(href:string,base:string):URL|null{
  // Escaped markup (href=&quot;...&quot;) decodes to quoted values: strip stray quotes and backslashes.
  const h=decode(href.trim()).replace(/^[\\"'\s]+|[\\"'\s]+$/g,"");if(!h||/["\\]/.test(h)||/^(#|javascript:|mailto:|tel:|data:)/i.test(h))return null;
  try{const u=new URL(h,base||undefined);if(!/^https?:$/.test(u.protocol))return null;u.hash="";return u}catch{return null}
}
function fromHtml(html:string,base:string,out:Map<string,{text:string}>){
  const re=/<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)<\/a>/gi;let m:RegExpExecArray|null;
  while((m=re.exec(html))&&out.size<MAX_LINKS){const u=resolve(m[1]??m[2]??m[3]??"",base);if(u&&!out.has(u.href))out.set(u.href,{text:clean(m[4]||"")})}
}
function fromMarkdown(md:string,base:string,out:Map<string,{text:string}>){
  const re=/\[([^\]]{0,200})\]\((\S+?)(?:\s+"[^"]*")?\)/g;let m:RegExpExecArray|null;
  while((m=re.exec(md))&&out.size<MAX_LINKS){const u=resolve(m[2],base);if(u&&!out.has(u.href))out.set(u.href,{text:clean(m[1])})}
}
// Walk Firecrawl-style JSON: "links" arrays, and any html/rawHtml/markdown strings.
function fromJson(v:any,base:string,out:Map<string,{text:string}>,depth=0){
  if(depth>6||out.size>=MAX_LINKS||v==null)return;
  if(Array.isArray(v)){for(const x of v)fromJson(x,base,out,depth+1);return}
  if(typeof v!=="object")return;
  for(const[k,x]of Object.entries(v)){
    if(k==="links"&&Array.isArray(x)){for(const l of x){const href=typeof l==="string"?l:(l?.url||l?.href||"");const u=resolve(String(href),base);if(u&&!out.has(u.href))out.set(u.href,{text:clean(String(l?.text||l?.title||""))});if(out.size>=MAX_LINKS)break}}
    else if(typeof x==="string"&&(k==="html"||k==="rawHtml"||k==="raw_html"))fromHtml(x,base,out);
    else if(typeof x==="string"&&k==="markdown")fromMarkdown(x,base,out);
    else if(typeof x==="object")fromJson(x,base,out,depth+1);
  }
}
function baseFromJson(v:any):string{try{return String(v?.metadata?.sourceURL||v?.metadata?.url||v?.data?.metadata?.sourceURL||v?.url||v?.source_url||"")}catch{return""}}

async function indexOne(svc:any,a:any){
  try{
    const{data,error}=await svc.storage.from("evidence").download(a.path);
    if(error||!data)throw Error(`download: ${error?.message||"not found"}`);
    if(data.size>MAX_BYTES){await rpc(svc,"svc_evidence_link_index_record_v1",{p_evidence_id:a.id,p_status:"unsupported",p_links:[],p_error:`too large (${data.size} bytes)`});return{status:"unsupported",links:0}}
    const text=await data.text();const out=new Map<string,{text:string}>();let base=String(a.url||"");
    if(/json/i.test(a.mime||"")){let j:any;try{j=JSON.parse(text)}catch{throw Error("invalid json")}base=base||baseFromJson(j);fromJson(j,base,out)}
    else fromHtml(text,base,out);
    const own=base?(()=>{try{return siteOf(new URL(base).hostname)}catch{return""}})():"";
    const links=[...out].map(([url,v])=>{const host=new URL(url).hostname.toLowerCase();const s=siteOf(host);return{url,host,text:v.text,same_site:!!own&&(s===own||s.endsWith("."+own)||own.endsWith("."+s))}});
    const n=await rpc(svc,"svc_evidence_link_index_record_v1",{p_evidence_id:a.id,p_status:"indexed",p_links:links,p_error:null});
    return{status:n>0?"indexed":"no_links",links:n};
  }catch(e:any){
    await rpc(svc,"svc_evidence_link_index_record_v1",{p_evidence_id:a.id,p_status:"error",p_links:[],p_error:String(e?.message||e)}).catch(()=>{});
    return{status:"error",links:0};
  }
}

Deno.serve(async req=>{
  try{
    if(req.method==="OPTIONS")return new Response(null,{status:204,headers:H()});
    if(req.method!=="POST")return J(405,{error:"method_not_allowed"});
    const sb=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const svc=createClient(sb,sk,{auth:{persistSession:false}});
    try{await auth(req,svc,sb,anon)}catch(e:any){return J(String(e.message).includes("role")?403:401,{error:String(e.message)})}
    const b=await req.json().catch(()=>({}));const limit=Math.max(1,Math.min(Number(b.limit)||60,200));
    const batch:any[]=await rpc(svc,"svc_evidence_link_index_next_v1",{p_limit:limit})||[];
    const started=Date.now(),summary:Record<string,number>={indexed:0,no_links:0,unsupported:0,error:0},C=6;let links=0,i=0;
    while(i<batch.length&&Date.now()-started<110_000){
      const res=await Promise.all(batch.slice(i,i+C).map(a=>indexOne(svc,a)));i+=C;
      for(const r of res){summary[r.status]=(summary[r.status]||0)+1;links+=r.links}
    }
    return J(200,{ok:true,processed:Math.min(i,batch.length),of:batch.length,links,summary,ms:Date.now()-started});
  }catch(e:any){return J(500,{error:String(e?.message||e)})}
});
