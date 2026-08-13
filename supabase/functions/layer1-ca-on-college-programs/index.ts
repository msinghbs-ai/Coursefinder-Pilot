import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import * as XLSX from "npm:xlsx@0.18.5";

const VERSION = "layer1-ca-on-college-programs-v0.1.0";
const DATASET_ID = "7219841a-892c-4cbd-ad01-1c702af7cfc6";
const CKAN = `https://data.ontario.ca/api/3/action/package_show?id=${DATASET_ID}`;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cf-pilot-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json=(body:any,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"content-type":"application/json","cache-control":"no-store"}});
const clean=(v:any)=>String(v??"").trim();
const norm=(v:any)=>clean(v).toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g,"").replace(/&/g," and ").replace(/[^a-z0-9]+/g," ").trim();
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw new Error(`${n}: ${error.message}`);return data;}
async function fetchT(url:string,ms=60000,init:RequestInit={}){const ctrl=new AbortController(),t=setTimeout(()=>ctrl.abort(),ms);try{return await fetch(url,{...init,signal:ctrl.signal,redirect:"follow",headers:{"user-agent":"coursefinder-pilot-ca-on/0.1",...(init.headers||{})}})}finally{clearTimeout(t)}}
async function sha(bytes:Uint8Array){const d=await crypto.subtle.digest("SHA-256",bytes);return[...new Uint8Array(d)].map(x=>x.toString(16).padStart(2,"0")).join("")}

async function authorize(req:Request,service:any,url:string,anon:string){
  const pilot=clean(req.headers.get("x-cf-pilot-key"));
  if(pilot){const ok=await rpc(service,"svc_pilot_automation_authorize",{p_key:pilot});if(!ok)throw new Error("invalid pilot automation key");return{mode:"pilot_automation",userId:null};}
  const token=(req.headers.get("authorization")||"").replace(/^Bearer\s+/i,"");
  if(!token)throw new Error("authentication required");
  const client=createClient(url,anon,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false}});
  const got=await client.auth.getUser(token);if(got.error||!got.data.user)throw new Error("invalid user session");
  const allowed=await rpc(service,"svc_layer1_authorize_platform_admin",{p_user_id:got.data.user.id});if(!allowed)throw new Error("platform_admin required");
  return{mode:"platform_admin",userId:got.data.user.id};
}

function findHeader(rows:any[][]){
  let best={row:-1,score:-1,headers:[] as string[]};
  for(let i=0;i<Math.min(rows.length,30);i++){
    const hs=(rows[i]||[]).map(clean);const ns=hs.map(norm);let score=0;
    if(ns.some(x=>x.includes("approved program sequence")||x==="aps"||x.includes("aps code")||x.includes("aps number")))score+=5;
    if(ns.some(x=>x.includes("college")||x.includes("institution")))score+=4;
    if(ns.some(x=>x.includes("program title")||x.includes("programme title")||x==="program"||x==="programme"))score+=4;
    if(ns.some(x=>x.includes("mtcu")||x.includes("ministry program")))score+=2;
    if(ns.some(x=>x.includes("credential")))score+=2;
    if(ns.some(x=>x.includes("cip")))score+=2;
    if(score>best.score)best={row:i,score,headers:hs};
  }
  return best;
}
function indexOf(headers:string[],patterns:RegExp[]){const ns=headers.map(norm);for(let i=0;i<ns.length;i++)if(patterns.some(p=>p.test(ns[i])))return i;return-1;}
function field(row:any[],idx:number){return idx>=0?clean(row[idx]):""}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"POST required"},405);
  const url=Deno.env.get("SUPABASE_URL")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,anon=Deno.env.get("SUPABASE_ANON_KEY")||sk;
  const service=createClient(url,sk,{auth:{persistSession:false}});let jobId:any=null,source:any=null;
  try{
    const auth=await authorize(req,service,url,anon);const body=await req.json().catch(()=>({}));
    if(body.apply===true)return json({error:"Ontario Course APPLY is locked pending Provider mapping and stable local programme-key UAT",workerVersion:VERSION,blocker:"CA_FEDERATED_COURSE_SOURCE_COVERAGE_BLOCKER"},409);
    const sampleRows=Math.max(1,Math.min(Number(body.sampleRows??1000),5000));
    const sources=await rpc(service,"svc_layer1_resolve_sources",{p_country_code:"CA"});
    source=(sources||[]).find((x:any)=>String(x.source_label||x.label||"").toLowerCase().includes("ontario public college")||x.source_metadata?.regional_registration_scheme==="on_aps"||x.metadata?.regional_registration_scheme==="on_aps");
    if(!source)throw new Error("Ontario public-college programme source missing");
    jobId=await rpc(service,"svc_layer1_start_job",{p_country_code:"CA",p_source_id:source.source_id,p_payload:{country_code:"CA",province:"ON",apply:false,sample_rows:sampleRows,runtime:"supabase_edge",version:VERSION,mode:"ontario_xlsx_parser_uat",requested_by:auth.userId||auth.mode}});

    let downloadUrl="",resource:any=null;
    const pkg=await fetchT(CKAN,30000);if(pkg.ok){const data=await pkg.json();resource=(data?.result?.resources||[]).find((r:any)=>/xlsx/i.test(String(r.format||""))||/\.xlsx(?:$|\?)/i.test(String(r.url||"")));downloadUrl=clean(resource?.url);}
    if(!downloadUrl){const landing=clean(source.source_url||source.url)||"https://data.ontario.ca/dataset/ontario-public-college-programs-postsecondary-field-of-study-table";const page=await fetchT(landing,30000);const html=await page.text();const m=html.match(/https?:\/\/[^\"'<> ]+\.xlsx(?:\?[^\"'<> ]*)?/i)||html.match(/\/dataset\/[^\"'<> ]+\.xlsx(?:\?[^\"'<> ]*)?/i);if(m)downloadUrl=m[0].startsWith("http")?m[0]:`https://data.ontario.ca${m[0]}`;}
    if(!downloadUrl)throw new Error("Ontario XLSX resource URL not discovered");
    const fr=await fetchT(downloadUrl,60000);if(!fr.ok)throw new Error(`Ontario XLSX HTTP ${fr.status}`);const bytes=new Uint8Array(await fr.arrayBuffer());
    const hash=await sha(bytes),stamp=new Date().toISOString().replace(/[:.]/g,"-");const path=`regulatory/CA/ON/public-college-programs/${stamp}.xlsx`;
    const up=await service.storage.from("evidence").upload(path,bytes,{contentType:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",upsert:true});if(up.error)throw new Error(`evidence upload: ${up.error.message}`);
    const evidenceId=await rpc(service,"svc_layer1_record_evidence",{p_source_id:source.source_id,p_job_id:jobId,p_source_url:downloadUrl,p_storage_path:path,p_content_hash:hash,p_mime_type:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",p_metadata:{worker_version:VERSION,dataset_id:DATASET_ID,resource_id:resource?.id||null,resource_name:resource?.name||null,byte_size:bytes.length}});

    const wb=XLSX.read(bytes,{type:"array",cellDates:false});let selected:any=null;
    for(const name of wb.SheetNames){const rows=XLSX.utils.sheet_to_json<any[]>(wb.Sheets[name],{header:1,raw:false,defval:"",blankrows:false});const h=findHeader(rows);if(!selected||h.score>selected.header.score)selected={name,rows,header:h};}
    if(!selected||selected.header.row<0)throw new Error("Ontario workbook header row not detected");
    const headers=selected.header.headers;const idx={
      college:indexOf(headers,[/^college$/,/^college name$/,/(college|institution).*name/,/^institution$/]),
      title:indexOf(headers,[/program.*title/,/programme.*title/,/^program name$/, /^programme name$/]),
      aps:indexOf(headers,[/^aps$/, /approved program sequence/, /aps.*(code|number)/]),
      mtcu:indexOf(headers,[/mtcu/,/ministry.*program.*code/]),
      cip:indexOf(headers,[/^cip$/, /cip.*code/,/classification of instructional programs/]),
      credential:indexOf(headers,[/credential/,/level of study/]),
      localCode:indexOf(headers,[/(college|institution).*program.*code/,/(college|institution).*programme.*code/,/^program code$/, /^programme code$/]),
      status:indexOf(headers,[/status/,/active|suspend|cancel/])
    };
    const dataRows=selected.rows.slice(selected.header.row+1).filter((r:any[])=>r.some(x=>clean(x))).slice(0,sampleRows);
    const sample=dataRows.slice(0,25).map((r:any[])=>({college:field(r,idx.college),programTitle:field(r,idx.title),aps:field(r,idx.aps),mtcu:field(r,idx.mtcu),cip:field(r,idx.cip),credential:field(r,idx.credential),localProgramCode:field(r,idx.localCode),status:field(r,idx.status)}));
    const providers=[...new Map(dataRows.map((r:any[])=>[norm(field(r,idx.college)),field(r,idx.college)]).filter(([k,v])=>k&&v)).entries()].map(([key,name])=>({sourceEntityKey:`on-college:${key}`,name}));
    const diagnostics={sheet:selected.name,sheetNames:wb.SheetNames,headerRow:selected.header.row+1,headerScore:selected.header.score,headers,detectedColumns:idx,sampledRows:dataRows.length,providerCandidates:providers.length,rowsWithAps:dataRows.filter((r:any[])=>field(r,idx.aps)).length,rowsWithLocalProgramCode:dataRows.filter((r:any[])=>field(r,idx.localCode)).length,rowsWithTitle:dataRows.filter((r:any[])=>field(r,idx.title)).length};
    const result={country:"CA",province:"ON",mode:"dry-run",workerVersion:VERSION,status:"PASS",downloadUrl,evidenceId,evidenceHash:hash,downloadedBytes:bytes.length,diagnostics,sample,providerCandidates:providers.slice(0,100),identityDecision:{apsRole:"validation_registration_only",titleIdentityAllowed:false,baseCourseIdentityRequired:"verified IRCC DLI + stable institutional/source-local programme key",applyEnabled:false},nextGate:"verify source Provider -> IRCC DLI mappings and determine whether workbook exposes a stable institutional/source-local programme key"};
    await rpc(service,"svc_layer1_source_health",{p_source_id:source.source_id,p_success:true,p_error:null,p_metadata:{worker_version:VERSION,parser_gate:"authenticated_or_pilot_runtime_dry_run_pass",sampled_rows:dataRows.length,provider_candidates:providers.length,rows_with_aps:diagnostics.rowsWithAps,rows_with_local_program_code:diagnostics.rowsWithLocalProgramCode,evidence_hash:hash,apply_enabled:false}});
    await rpc(service,"svc_layer1_finish_job",{p_job_id:jobId,p_status:"completed",p_result:result,p_error:null});return json({ok:true,jobId,...result});
  }catch(e){const msg=e instanceof Error?e.message:String(e);if(jobId)try{await rpc(service,"svc_layer1_finish_job",{p_job_id:jobId,p_status:"failed",p_result:{workerVersion:VERSION},p_error:msg})}catch{};if(source)try{await rpc(service,"svc_layer1_source_health",{p_source_id:source.source_id,p_success:false,p_error:msg,p_metadata:{worker_version:VERSION}})}catch{};return json({error:msg,jobId,workerVersion:VERSION},500);}
});