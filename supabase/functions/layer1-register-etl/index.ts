import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "layer1-edge-v1.0.0";
const CHUNK = 250;
const DEMO_URL = "https://gfryvshbeptxwbzjomhe.supabase.co";
// Public publishable key used only to migrate the demo's read-only Layer 1 seed into Pilot.
const DEMO_PUBLISHABLE_KEY = "sb_publishable_KSkAiDfMolo69cGckAEQlQ_gzuyHuBY";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function parseCSV(text: string): string[][] {
  const rows:string[][]=[]; let row:string[]=[], field="", quoted=false;
  for(let i=0;i<text.length;i++){
    const ch=text[i];
    if(quoted){ if(ch==='"'){ if(text[i+1]==='"'){field+='"';i++;} else quoted=false; } else field+=ch; }
    else if(ch==='"') quoted=true;
    else if(ch===','){row.push(field);field="";}
    else if(ch==='\n'){row.push(field);rows.push(row);row=[];field="";}
    else if(ch!=='\r') field+=ch;
  }
  if(field.length||row.length){row.push(field);rows.push(row);} return rows;
}
async function hashBytes(bytes:Uint8Array){const h=await crypto.subtle.digest("SHA-256",bytes);return Array.from(new Uint8Array(h)).map(x=>x.toString(16).padStart(2,"0")).join("");}
async function fetchWithTimeout(url:string, ms=15000, init:RequestInit={}){const c=new AbortController();const t=setTimeout(()=>c.abort(),ms);try{return await fetch(url,{...init,signal:c.signal,redirect:"follow",headers:{"user-agent":"coursefinder-pilot/1.0",...(init.headers||{})}});}finally{clearTimeout(t);}}
function clean(s:any){return String(s??"").trim();}
function slug(s:string){return clean(s).toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"").slice(0,100);}
function mapLevel(raw:string){const s=clean(raw).toLowerCase();if(/doctor|phd/.test(s))return"doctorate";if(/master|m\.sc|m\.a\.|mba|ll\.m/.test(s))return"masters";if(/graduate certificate/.test(s))return"graduate_certificate";if(/graduate diploma/.test(s))return"graduate_diploma";if(/bachelor|b\.sc|b\.a\.|b\.eng/.test(s))return"bachelor";if(/associate/.test(s))return"associate_degree";if(/diploma/.test(s))return"diploma";if(/certificate/.test(s))return"certificate";if(/foundation/.test(s))return"foundation";return"";}

async function authAdmin(req:Request, service:any, url:string, key:string){
  const token=(req.headers.get("authorization")||"").replace(/^Bearer\s+/i,"");
  if(!token) throw new Error("authentication required");
  const userClient=createClient(url,key,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false}});
  const {data:{user},error}=await userClient.auth.getUser(token); if(error||!user) throw new Error("invalid user session");
  const {data:allowed,error:ae}=await service.rpc("svc_layer1_authorize_platform_admin",{p_user_id:user.id}); if(ae)throw new Error(ae.message); if(!allowed)throw new Error("platform_admin required");
  return user;
}
async function resolve(service:any,cc:string){const {data,error}=await service.rpc("svc_layer1_resolve_sources",{p_country_code:cc});if(error)throw new Error(`resolve ${cc}: ${error.message}`);return data||[];}
async function startJob(service:any,cc:string,sourceId:string,payload:any){const {data,error}=await service.rpc("svc_layer1_start_job",{p_country_code:cc,p_source_id:sourceId,p_payload:payload});if(error)throw new Error(error.message);return data;}
async function finishJob(service:any,id:string,status:string,result:any,errorText:string|null=null){const {error}=await service.rpc("svc_layer1_finish_job",{p_job_id:id,p_status:status,p_result:result,p_error:errorText});if(error)console.error("finish job",error.message);}
async function sourceHealth(service:any,id:string,success:boolean,errorText:string|null,metadata:any){const {error}=await service.rpc("svc_layer1_source_health",{p_source_id:id,p_success:success,p_error:errorText,p_metadata:metadata});if(error)console.error("source health",error.message);}
async function evidence(service:any,sourceId:string,jobId:string,url:string,path:string,bytes:Uint8Array,mime:string,metadata:any){
  const h=await hashBytes(bytes); const up=await service.storage.from("evidence").upload(path,bytes,{contentType:mime,upsert:true}); if(up.error)throw new Error(`evidence upload: ${up.error.message}`);
  const {data:id,error}=await service.rpc("svc_layer1_record_evidence",{p_source_id:sourceId,p_job_id:jobId,p_source_url:url,p_storage_path:path,p_content_hash:h,p_mime_type:mime,p_metadata:metadata});if(error)throw new Error(error.message);return{id,hash:h,path};
}
async function applyRecords(service:any,cc:string,sourceId:string,evidenceId:string|null,scheme:string,records:any[],apply:boolean,maxRecords:number){
  const selected=maxRecords>0?records.slice(0,maxRecords):records; const total={records:selected.length,provider_created:0,provider_linked:0,provider_existing:0,course_created:0,course_linked:0,course_existing:0,conflicts:0};
  if(!apply)return total;
  for(let i=0;i<selected.length;i+=CHUNK){const {data,error}=await service.rpc("svc_layer1_apply_register_records",{p_country_code:cc,p_source_id:sourceId,p_evidence_id:evidenceId,p_registration_scheme:scheme,p_records:selected.slice(i,i+CHUNK)});if(error)throw new Error(error.message);for(const k of Object.keys(total)) if(k!=="records") (total as any)[k]+=Number(data?.[k]||0);}
  return total;
}

async function bootstrapSeed(service:any,cc:string){
  let {data,error}=await service.rpc("svc_layer1_get_seed_snapshot",{p_country_code:cc});if(error)throw new Error(error.message);if(Array.isArray(data)&&data.length)return data;
  const demo=createClient(DEMO_URL,DEMO_PUBLISHABLE_KEY,{auth:{persistSession:false}});
  const q=await demo.from("demo_snapshot").select("country_code,provider_name,website,city,register,register_code,register_name,register_url,courses").eq("country_code",cc).order("provider_name");
  if(q.error)throw new Error(`seed bootstrap ${cc}: ${q.error.message}`); if(!q.data?.length)throw new Error(`no demo Layer 1 seed for ${cc}`);
  const snapshot=q.data.map((p:any)=>({n:p.provider_name,w:p.website,c:p.city,s:p.register,p:p.register_code,u:p.register_url,q:(p.courses||[]).map((x:any)=>[x.title,x.level_code,x.register_code,x.duration_weeks,x.field_of_study])}));
  const put=await service.rpc("svc_layer1_put_seed_snapshot",{p_country_code:cc,p_snapshot:snapshot,p_seed_source:"coursefinder-demo-layer1-core",p_seed_version:"2026-08-11"});if(put.error)throw new Error(put.error.message);return snapshot;
}
function expandSeed(snapshot:any[]){const out:any[]=[];for(const p of snapshot){for(const c of p.q||[]){out.push({provider_code:p.p,provider_name:p.n,website:p.w,city:p.c,course_name:c[0],course_level:c[1],course_code:c[2],duration_weeks:c[3],field_of_study:c[4]});}if(!(p.q||[]).length)out.push({provider_code:p.p,provider_name:p.n,website:p.w,city:p.c});}return out;}
async function runSeedCountry(service:any,cc:string,sources:any[],apply:boolean,maxRecords:number,userId:string){
  const source=sources[0]; if(!source)throw new Error(`${cc}: no configured source`); const snapshot=await bootstrapSeed(service,cc); const records=expandSeed(snapshot); const scheme=clean(snapshot[0]?.s||source.system_code||cc).toLowerCase();
  const jobId=await startJob(service,cc,source.source_id,{country_code:cc,apply,max_records:maxRecords,runtime:"supabase_edge",version:VERSION,mode:"seed_snapshot",requested_by:userId});
  try{
    let reachable=false,httpStatus:null|number=null,liveError:string|null=null;
    try{const r=await fetchWithTimeout(source.source_url||source.system_base_url,10000);httpStatus=r.status;reachable=r.ok;await r.body?.cancel();}catch(e){liveError=String(e).slice(0,300);}
    const bytes=new TextEncoder().encode(JSON.stringify(snapshot)); const stamp=new Date().toISOString().replace(/[:.]/g,"-"); const ev=await evidence(service,source.source_id,jobId,source.source_url||source.system_base_url,`regulatory/${cc}/seed/${stamp}.json`,bytes,"application/json",{country:cc,mode:"seed_snapshot",live_reachable:reachable,http_status:httpStatus});
    const rec=await applyRecords(service,cc,source.source_id,ev.id,scheme,records,apply,maxRecords);
    const result={country:cc,mode:apply?"apply":"dry-run",adapter:"seed_snapshot",parsedRecords:records.length,selectedRecords:maxRecords>0?Math.min(maxRecords,records.length):records.length,reconciliation:rec,evidenceIds:[ev.id],freshness:{reachable,httpStatus,error:liveError},workerVersion:VERSION};
    await sourceHealth(service,source.source_id,reachable,liveError,{worker_version:VERSION,last_run_mode:apply?"apply":"dry-run",last_run_records:result.selectedRecords,seed_snapshot:true}); await finishJob(service,jobId,"completed",result); return{...result,jobId};
  }catch(e){const msg=String(e).slice(0,2000);await sourceHealth(service,source.source_id,false,msg,{worker_version:VERSION});await finishJob(service,jobId,"failed",{worker_version:VERSION},msg);throw e;}
}

async function runAU(service:any,sources:any[],apply:boolean,maxRecords:number,userId:string){
  const source=sources.find((x:any)=>x.system_code==="au_cricos")||sources[0]; if(!source)throw new Error("AU source missing"); const jobId=await startJob(service,"AU",source.source_id,{country_code:"AU",apply,max_records:maxRecords,runtime:"supabase_edge",version:VERSION,mode:"live",requested_by:userId});
  try{
    const discovery=source.source_metadata?.discovery_url||source.system_config?.discovery_url||"https://data.gov.au/data/api/3/action/package_show?id=cricos"; const pkg=await (await fetchWithTimeout(discovery,20000)).json(); if(!pkg?.success)throw new Error("CRICOS discovery failed");
    const resources=(pkg.result?.resources||[]).filter((r:any)=>String(r.format||"").toUpperCase()==="CSV"); const inst=resources.find((r:any)=>/Institutions/i.test(r.name||"")); const courses=resources.find((r:any)=>/^CRICOS Courses\.csv$/i.test(r.name||""))||resources.find((r:any)=>/Courses/i.test(r.name||"")); if(!inst||!courses)throw new Error("CRICOS Institutions/Courses CSV not found");
    const [ir,cr]=await Promise.all([fetchWithTimeout(inst.url,30000),fetchWithTimeout(courses.url,30000)]); if(!ir.ok||!cr.ok)throw new Error(`CRICOS CSV HTTP ${ir.status}/${cr.status}`); const [it,ct]=await Promise.all([ir.text(),cr.text()]);
    const stamp=new Date().toISOString().replace(/[:.]/g,"-"); const iev=await evidence(service,source.source_id,jobId,inst.url,`regulatory/AU/cricos/${stamp}-institutions.csv`,new TextEncoder().encode(it),"text/csv",{resource_name:inst.name}); const cev=await evidence(service,source.source_id,jobId,courses.url,`regulatory/AU/cricos/${stamp}-courses.csv`,new TextEncoder().encode(ct),"text/csv",{resource_name:courses.name});
    const pi=parseCSV(it),pc=parseCSV(ct),ih=pi[0]||[],ch=pc[0]||[];const ix=(n:string)=>ih.indexOf(n),cx=(n:string)=>ch.indexOf(n);const providers=new Map<string,any>();
    for(const r of pi.slice(1)){const code=clean(r[ix("CRICOS Provider Code")]);const name=clean(r[ix("Trading Name")])||clean(r[ix("Institution Name")]);if(!code||!name)continue;let website=clean(r[ix("Website")]);if(website&&!/^https?:\/\//i.test(website))website="https://"+website;providers.set(code,{name,website:website||null,city:clean(r[ix("Postal Address City")])||null});}
    const records:any[]=[];for(const r of pc.slice(1)){if(clean(r[cx("Expired")])!=="No")continue;const pcode=clean(r[cx("CRICOS Provider Code")]);const p=providers.get(pcode);if(!p)continue;const code=clean(r[cx("CRICOS Course Code")]),title=clean(r[cx("Course Name")]);if(!code||!title)continue;records.push({provider_code:pcode,provider_name:p.name,website:p.website,city:p.city,course_code:code,course_name:title,course_level:mapLevel(clean(r[cx("Course Level")])),duration_weeks:clean(r[cx("Duration (Weeks)")]),field_of_study:clean(r[cx("Field of Education 1 Narrow Field")]).replace(/^[0-9]+ - /,"")});}
    const rec=await applyRecords(service,"AU",source.source_id,cev.id,"cricos",records,apply,maxRecords);const result={country:"AU",mode:apply?"apply":"dry-run",adapter:"cricos_live",parsedRecords:records.length,selectedRecords:maxRecords>0?Math.min(maxRecords,records.length):records.length,reconciliation:rec,evidenceIds:[iev.id,cev.id],workerVersion:VERSION};
    await sourceHealth(service,source.source_id,true,null,{worker_version:VERSION,parsed_records:records.length,institution_hash:iev.hash,course_hash:cev.hash,last_run_mode:result.mode,last_run_records:result.selectedRecords});await finishJob(service,jobId,"completed",result);return{...result,jobId};
  }catch(e){const msg=String(e).slice(0,2000);await sourceHealth(service,source.source_id,false,msg,{worker_version:VERSION});await finishJob(service,jobId,"failed",{worker_version:VERSION},msg);throw e;}
}

async function runGB(service:any,sources:any[],apply:boolean,maxRecords:number,userId:string){
  const live=sources.find((x:any)=>x.system_code==="gb_ukvi_student_sponsors"); let liveSummary:any=null;
  if(live){const jobId=await startJob(service,"GB",live.source_id,{country_code:"GB",apply,max_records:maxRecords,runtime:"supabase_edge",version:VERSION,mode:"live_provider_register",requested_by:userId});try{const page=await fetchWithTimeout(live.source_url||live.system_base_url,15000);const html=await page.text();const csvUrl=html.match(/https:\/\/assets\.publishing\.service\.gov\.uk[^\"']+?\.csv/)?.[0];if(!csvUrl)throw new Error("UKVI CSV asset not found");const rr=await fetchWithTimeout(csvUrl,30000);if(!rr.ok)throw new Error(`UKVI CSV HTTP ${rr.status}`);const text=await rr.text();const rows=parseCSV(text),head=rows[0]||[],hx=(n:string)=>head.indexOf(n);const records:any[]=[];for(const r of rows.slice(1)){if(!clean(r[hx("Sponsor Type")]).includes("Higher Education"))continue;if(clean(r[hx("Route")])!=="Student")continue;const name=clean(r[hx("Sponsor Name")]);if(name)records.push({provider_code:slug(name),provider_name:name,city:clean(r[hx("Town/City")])||null});}const stamp=new Date().toISOString().replace(/[:.]/g,"-");const ev=await evidence(service,live.source_id,jobId,csvUrl,`regulatory/GB/ukvi/${stamp}.csv`,new TextEncoder().encode(text),"text/csv",{provider_rows:records.length});const rec=await applyRecords(service,"GB",live.source_id,ev.id,"uk_sponsor",records,apply,0);liveSummary={adapter:"ukvi_live",parsedRecords:records.length,reconciliation:rec,evidenceIds:[ev.id]};await sourceHealth(service,live.source_id,true,null,{worker_version:VERSION,parsed_records:records.length});await finishJob(service,jobId,"completed",liveSummary);}catch(e){const msg=String(e).slice(0,1500);liveSummary={adapter:"ukvi_live",error:msg};await sourceHealth(service,live.source_id,false,msg,{worker_version:VERSION});await finishJob(service,jobId,"failed",liveSummary,msg);}}
  const seed=await runSeedCountry(service,"GB",sources.filter((x:any)=>x.system_code!=="gb_ukvi_student_sponsors"),apply,maxRecords,userId);return{...seed,liveProviderRegister:liveSummary};
}

async function runDE(service:any,sources:any[],apply:boolean,maxRecords:number,userId:string){
  const source=sources.find((x:any)=>x.system_code==="de_daad_programmes")||sources[0];if(!source)throw new Error("DE source missing");const jobId=await startJob(service,"DE",source.source_id,{country_code:"DE",apply,max_records:maxRecords,runtime:"supabase_edge",version:VERSION,mode:"live",requested_by:userId});
  try{const api=source.system_config?.api_url||"https://www2.daad.de/deutschland/studienangebote/international-programmes/api/solr";const url=`${api}/en/search.json?q=&sort=4&page=1`;const r=await fetchWithTimeout(url,30000,{headers:{accept:"application/json"}});if(!r.ok)throw new Error(`DAAD HTTP ${r.status}`);const data=await r.json();const courses=data.courses||[];const records=courses.filter((c:any)=>c.courseName&&c.academy).map((c:any)=>({provider_code:slug(c.academy),provider_name:c.academy,city:c.city||null,course_code:String(c.id),course_name:c.courseName,course_level:mapLevel(c.courseName),field_of_study:c.subject||null}));const bytes=new TextEncoder().encode(JSON.stringify({numResults:data.numResults,courses:courses}));const stamp=new Date().toISOString().replace(/[:.]/g,"-");const ev=await evidence(service,source.source_id,jobId,url,`regulatory/DE/daad/${stamp}.json`,bytes,"application/json",{num_results:data.numResults});const rec=await applyRecords(service,"DE",source.source_id,ev.id,"daad",records,apply,maxRecords);const result={country:"DE",mode:apply?"apply":"dry-run",adapter:"daad_live",parsedRecords:records.length,availableRecords:data.numResults,selectedRecords:maxRecords>0?Math.min(maxRecords,records.length):records.length,reconciliation:rec,evidenceIds:[ev.id],workerVersion:VERSION};await sourceHealth(service,source.source_id,true,null,{worker_version:VERSION,parsed_records:records.length,available_records:data.numResults});await finishJob(service,jobId,"completed",result);return{...result,jobId};}catch(e){const msg=String(e).slice(0,2000);await sourceHealth(service,source.source_id,false,msg,{worker_version:VERSION});await finishJob(service,jobId,"failed",{worker_version:VERSION},msg);throw e;}
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors}); if(req.method!=="POST")return json({error:"POST required"},405);
  const url=Deno.env.get("SUPABASE_URL")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,publishable=Deno.env.get("SUPABASE_ANON_KEY")||Deno.env.get("SUPABASE_PUBLISHABLE_KEY")||"";const service=createClient(url,serviceKey,{auth:{persistSession:false}});
  try{
    const user=await authAdmin(req,service,url,publishable||serviceKey);const body=await req.json().catch(()=>({}));const requested=String(body.country||"ALL").toUpperCase();const apply=Boolean(body.apply);const maxRecords=Math.max(0,Math.min(Number(body.maxRecords??100),30000));const countries=requested==="ALL"?["AU","GB","DE","CA","IE","NZ","US"]:[requested];const results:any[]=[],failures:any[]=[];
    for(const cc of countries){try{const sources=await resolve(service,cc);let res:any;if(cc==="AU")res=await runAU(service,sources,apply,maxRecords,user.id);else if(cc==="GB")res=await runGB(service,sources,apply,maxRecords,user.id);else if(cc==="DE")res=await runDE(service,sources,apply,maxRecords,user.id);else if(["CA","IE","NZ","US"].includes(cc))res=await runSeedCountry(service,cc,sources,apply,maxRecords,user.id);else throw new Error(`No Layer 1 adapter for ${cc}`);results.push(res);}catch(e){failures.push({country:cc,error:String(e).slice(0,1200)});}}
    let catalogueStats=null;if(apply&&results.length){const fin=await service.rpc("svc_layer1_finalize_catalogue");if(fin.error)throw new Error(`finalise: ${fin.error.message}`);catalogueStats=fin.data;}
    const seed=await service.rpc("svc_layer1_seed_status");return json({ok:failures.length===0,status:failures.length?"completed_with_errors":"completed",mode:apply?"apply":"dry-run",requestedCountry:requested,maxRecords,countries:results,failures,catalogueStats,seedStatus:seed.data||[],workerVersion:VERSION,runtime:"supabase_edge"},failures.length&&results.length===0?500:200);
  }catch(e){console.error(e);return json({error:String(e),workerVersion:VERSION},500);}
});