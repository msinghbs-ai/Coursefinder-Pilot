import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import * as XLSX from "npm:xlsx@0.18.5";

const VERSION="ranking-layer1-etl-v1.4.0";
const QS_STATIC:Record<number,string>={2026:"4061771"};
const QS_REST:Record<number,string>={2027:"4153156"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
const clean=(v:unknown)=>String(v??"").replace(/^\uFEFF/,"").trim();
const key=(v:unknown)=>clean(v).toLowerCase().replace(/[^a-z0-9]+/g," ").trim();
async function sha(bytes:Uint8Array){const d=await crypto.subtle.digest("SHA-256",bytes);return[...new Uint8Array(d)].map(x=>x.toString(16).padStart(2,"0")).join("")}
function decodeHtml(s:string){return s.replace(/&amp;/g,"&").replace(/&#039;|&apos;/g,"'").replace(/&quot;/g,'"').replace(/&nbsp;/g," ").replace(/&ndash;|&#8211;/g,"–").replace(/&mdash;|&#8212;/g,"—").replace(/&lt;/g,"<").replace(/&gt;/g,">")}
function stripHtml(s:unknown){return decodeHtml(clean(s).replace(/<br\s*\/?\s*>/gi," ").replace(/<[^>]*>/g," ").replace(/\s+/g," ").trim())}
function pick(row:Record<string,unknown>,aliases:string[]){const map=new Map(Object.entries(row).map(([k,v])=>[key(k),v]));for(const a of aliases){const v=map.get(key(a));if(v!==undefined&&clean(v)!=="")return clean(v)}return""}
function findRank(row:Record<string,unknown>,year:number){const direct=pick(row,["rank","world rank","ranking","rank "+year,"world university rank","world university ranking","world university rankings"]);if(direct)return direct;for(const[k,v]of Object.entries(row)){const kk=key(k);if((kk===String(year)||kk.includes(String(year)))&&/(rank|ranking|world)/.test(kk)&&clean(v))return clean(v)}return""}
function parseRank(raw:string){
 const display=stripHtml(raw).replace(/^#\s*/,"");const norm=display.replace(/[–—]/g,"-").replace(/,/g,"").trim();
 if(!norm)return{rank_display:"",rank_exact:null,rank_low:null,rank_high:null,is_tied:false,rank_status:"unknown"};
 if(/reporter/i.test(norm))return{rank_display:display,rank_exact:null,rank_low:null,rank_high:null,is_tied:false,rank_status:"reporter"};
 if(/not\s*ranked|unranked|n\/a|^-$|^—$/i.test(norm))return{rank_display:display,rank_exact:null,rank_low:null,rank_high:null,is_tied:false,rank_status:"unranked"};
 const tied=/^=/.test(norm);const x=norm.replace(/^=/,"");
 const band=x.match(/^(\d+)\s*-\s*(\d+)$/);if(band)return{rank_display:display,rank_exact:null,rank_low:Number(band[1]),rank_high:Number(band[2]),is_tied:tied,rank_status:"ranked_band"};
 const plus=x.match(/^(\d+)\+$/);if(plus)return{rank_display:display,rank_exact:null,rank_low:Number(plus[1]),rank_high:null,is_tied:tied,rank_status:"ranked_band"};
 const exact=x.match(/^(\d+)$/);if(exact)return{rank_display:display,rank_exact:Number(exact[1]),rank_low:null,rank_high:null,is_tied:tied,rank_status:"ranked_exact"};
 return{rank_display:display,rank_exact:null,rank_low:null,rank_high:null,is_tied:tied,rank_status:"unknown"};
}
function score(raw:unknown){const s=stripHtml(raw);if(!s||s==="-"||s==="—")return null;const n=Number(s.replace(/,/g,""));return Number.isFinite(n)?n:null}
function qsName(uni:unknown){const html=clean(uni);const m=html.match(/<a[^>]*class=["'][^"']*uni-link[^"']*["'][^>]*>([\s\S]*?)<\/a>/i);return stripHtml(m?.[1]||html)}
function qsPath(uni:unknown){const m=clean(uni).match(/<a[^>]*href=["']([^"']+)["'][^>]*class=["'][^"']*uni-link/i)||clean(uni).match(/<a[^>]*class=["'][^"']*uni-link[^"']*["'][^>]*href=["']([^"']+)["']/i);return m?.[1]||null}
function qsRows(data:any[]){
 return data.map((r:any,i:number)=>{const parsed=parseRank(r.overall_rank_dis||r.overall_rank||"");const indicators=Object.fromEntries(Object.entries(r).filter(([k])=>/^ind_\d+$/.test(k)).map(([k,v])=>[k,score(v)]));return{
  publisher_institution_id:clean(r.nid)||null,institution_name:qsName(r.uni),profile_url:qsPath(r.uni),country_text:clean(r.location)||null,location_text:[clean(r.city),clean(r.location)].filter(Boolean).join(", ")||null,
  rank_display:parsed.rank_display||null,rank_exact:parsed.rank_exact,rank_low:parsed.rank_low,rank_high:parsed.rank_high,is_tied:parsed.is_tied,rank_status:parsed.rank_status,
  overall_score:score(r.overall),source_row_ordinal:i+1,indicators,source_row_payload:r
 }}).filter((r:any)=>r.institution_name)
}
function rowsFromWorkbook(bytes:Uint8Array,year:number,systemCode:string,originalFilename:string){
 const wb=XLSX.read(bytes,{type:"array",cellDates:false,raw:false});let best:any[]=[];for(const name of wb.SheetNames){const rows=XLSX.utils.sheet_to_json<Record<string,unknown>>(wb.Sheets[name],{defval:"",raw:false});if(rows.length>best.length)best=rows}
 const headers=best.length?Object.keys(best[0]).map(key):[],qsCompact=headers.includes(key(`qs_world_rank_${year}`)),theCompact=headers.includes(key(`the_world_rank_${year}`));
 const compact=qsCompact||theCompact,scopeCountry=/australia/i.test(originalFilename)?"Australia":null;
 if(compact&&!scopeCountry&&!headers.some(h=>/^(country|location|country territory|country region)$/.test(h)))throw new Error("Compact ranking CSV requires an explicit country/location column or a country-scoped filename such as Australia");
 const out:any[]=[];let ordinal=0;
 for(const row of best){ordinal++;const institution=pick(row,["institution name","university","university name","name","institution"]);if(!institution)continue;
  const country=pick(row,["location","country territory","country/territory","country region","country/region","country"])||scopeCountry||"";
  const rankRaw=qsCompact?pick(row,[`qs_world_rank_${year}`]):theCompact?pick(row,[`the_world_rank_${year}`]):findRank(row,year),parsed=parseRank(rankRaw);
  const overallRaw=theCompact?pick(row,[`the_overall_score_${year}`]):pick(row,["overall score","overall","score"]),overall=scoreParts(overallRaw);
  const indicators=theCompact?{overall:indicator("Overall",overallRaw,"score",String(year))}:{};
  out.push({institution_name:institution,country_text:country||null,rank_display:parsed.rank_display||null,rank_exact:parsed.rank_exact,rank_low:parsed.rank_low,rank_high:parsed.rank_high,is_tied:parsed.is_tied,rank_status:parsed.rank_status,overall_score:overall.numeric,overall_score_display:overall.display,overall_score_low:overall.low,overall_score_high:overall.high,source_row_ordinal:ordinal,indicators,source_row_payload:row})
 }
 return out
}

function scoreParts(raw:unknown){
 const display=stripHtml(raw);if(!display||display==="-"||display==="—")return{display:null,numeric:null,low:null,high:null};
 const norm=display.replace(/[–—]/g,"-").replace(/,/g,"").trim();
 const range=norm.match(/^(-?\d+(?:\.\d+)?)\s*-\s*(-?\d+(?:\.\d+)?)$/);if(range)return{display,numeric:null,low:Number(range[1]),high:Number(range[2])};
 const n=Number(norm);return Number.isFinite(n)?{display,numeric:n,low:null,high:null}:{display,numeric:null,low:null,high:null};
}
function indicator(label:string,raw:unknown,unit="score",methodologyVersion:string|null=null){
 const p=scoreParts(raw);return{label,value_display:p.display,value_numeric:p.numeric,unit,methodology_version:methodologyVersion};
}
function theRowsFromNativeJson(bytes:Uint8Array,expectedYear:number){
 let text=new TextDecoder().decode(bytes).replace(/^\uFEFF/,"").trim(),declaredYear:null|number=null;
 const hm=text.match(/^Year\s+(\d{4})\s*[\r\n]+/i);if(hm){declaredYear=Number(hm[1]);text=text.slice(hm[0].length);}
 if(declaredYear!==null&&declaredYear!==expectedYear)throw new Error(`THE file year ${declaredYear} does not match selected edition ${expectedYear}`);
 const payload=JSON.parse(text);if(String(payload?.status||"").toLowerCase()!=="success")throw new Error("THE JSON status is not success");
 const data=payload?.data?.data;if(!Array.isArray(data))throw new Error("THE JSON payload missing data.data array");
 const rows=data.map((r:any,i:number)=>{const parsed=parseRank(r.rank||""),overall=scoreParts(r.scores_overall);return{
  publisher_institution_id:clean(r.nid||r.iid)||null,institution_name:clean(r.name),profile_url:clean(r.url)||null,country_text:clean(r.location)||null,location_text:clean(r.location)||null,
  rank_display:parsed.rank_display||null,rank_exact:parsed.rank_exact,rank_low:parsed.rank_low,rank_high:parsed.rank_high,is_tied:parsed.is_tied,rank_status:parsed.rank_status,
  overall_score:overall.numeric,overall_score_display:overall.display,overall_score_low:overall.low,overall_score_high:overall.high,source_row_ordinal:i+1,
  indicators:{
   overall:indicator("Overall",r.scores_overall,"score",String(expectedYear)),
   teaching:indicator("Teaching",r.scores_teaching,"score",String(expectedYear)),
   research:indicator("Research",r.scores_research,"score",String(expectedYear)),
   citations:indicator("Citations",r.scores_citations,"score",String(expectedYear)),
   industry_income:indicator("Industry Income",r.scores_industry_income,"score",String(expectedYear)),
   international_outlook:indicator("International Outlook",r.scores_international_outlook,"score",String(expectedYear))
  },source_row_payload:r
 }}).filter((r:any)=>r.institution_name);
 return{rows,declaredYear,publisherStatus:payload?.status};
}

async function fetchQsStatic(year:number){
 const nid=QS_STATIC[year];if(!nid)return null;
 const url=`https://www.topuniversities.com/sites/default/files/qs-rankings-data/en/${nid}_indicators.txt`;
 const r=await fetch(url,{headers:{"User-Agent":"Mozilla/5.0","X-Requested-With":"XMLHttpRequest","Accept":"application/json","Referer":"https://www.topuniversities.com/world-university-rankings"}});
 if(!r.ok)throw new Error(`QS static XHR HTTP ${r.status}`);
 const text=await r.text(),bytes=new TextEncoder().encode(text);const payload=JSON.parse(text);if(!Array.isArray(payload?.data))throw new Error("QS static XHR payload missing data array");
 return{url,nid,bytes,text,payload,rows:qsRows(payload.data)};
}
async function fetchQsRest(year:number){
 const nid=QS_REST[year];if(!nid)return null;
 const all:any[]=[];let page=0;const raw:any[]=[];
 while(page<20){const url=`https://www.topuniversities.com/rankings/endpoint?nid=${nid}&page=${page}&items_per_page=500&tab=indicators`;const r=await fetch(url,{headers:{"User-Agent":"Mozilla/5.0","Accept":"application/json","X-Requested-With":"XMLHttpRequest","Referer":"https://www.topuniversities.com/world-university-rankings"}});if(r.status===403)return{blocked:true,status:403,url,nid};if(!r.ok)throw new Error(`QS REST HTTP ${r.status}`);const d=await r.json();const nodes=Array.isArray(d?.score_nodes)?d.score_nodes:[];raw.push(d);for(const n of nodes)all.push(n);if(nodes.length<500)break;page++}
 const text=JSON.stringify(raw),bytes=new TextEncoder().encode(text);
 const rows=all.map((n:any,i:number)=>{const parsed=parseRank(n.rank_display??n.rank??"");const indicators=Object.fromEntries(Object.entries(n).filter(([k,v])=>(/^ind_\d+$/.test(k)||/score/i.test(k))&&score(v)!==null).map(([k,v])=>[k,score(v)]));return{publisher_institution_id:clean(n.nid||n.id)||null,institution_name:clean(n.title),profile_url:clean(n.path)||null,country_text:clean(n.country)||null,location_text:[clean(n.city),clean(n.country)].filter(Boolean).join(", ")||null,rank_display:parsed.rank_display||null,rank_exact:parsed.rank_exact,rank_low:parsed.rank_low,rank_high:parsed.rank_high,is_tied:parsed.is_tied,rank_status:parsed.rank_status,overall_score:score(n.overall_score??n.score),source_row_ordinal:i+1,indicators,source_row_payload:n}}).filter((x:any)=>x.institution_name);
 return{url:`https://www.topuniversities.com/rankings/endpoint?nid=${nid}`,nid,bytes,text,payload:raw,rows};
}
async function retainJson(service:any,sourceId:string,systemCode:string,year:number,sourceUrl:string,nid:string,bytes:Uint8Array,rowCount:number,endpointKind:string){
 const hash=await sha(bytes),path=`ranking/${systemCode}/${year}/xhr-${hash}.json`;
 const up=await service.storage.from("evidence").upload(path,bytes,{contentType:"application/json",upsert:false});
 if(up.error&&!/already exists|duplicate/i.test(up.error.message))throw up.error;
 const {data:id,error}=await service.rpc("svc_ranking_source_snapshot_register",{p_source_id:sourceId,p_system_code:systemCode,p_edition_year:year,p_source_url:sourceUrl,p_storage_path:path,p_content_hash:hash,p_byte_size:bytes.length,p_metadata:{ranking_nid:nid,row_count:rowCount,endpoint_kind:endpointKind,worker_version:VERSION}});
 if(error)throw error;return{hash,path,evidenceArtifactId:id};
}

Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return json({error:"POST required",workerVersion:VERSION},405);
 const url=Deno.env.get("SUPABASE_URL")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;if(!url||!serviceKey)return json({error:"service configuration missing",workerVersion:VERSION},500);
 if((req.headers.get("x-cf-layer1-service-key")||"")!==serviceKey)return json({error:"service authorization required",workerVersion:VERSION},403);
 const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 try{
  const body=await req.json().catch(()=>({})),systemCode=clean(body.system_code),editionYear=Number(body.edition_year),mode=clean(body.mode||"dry_run").toLowerCase(),sourceId=clean(body.source_id);
  if(!["qs_wur","the_wur"].includes(systemCode))throw new Error("unsupported ranking system");if(!Number.isInteger(editionYear))throw new Error("edition_year required");
  let rows:any[]=[],sourceHash="",evidenceArtifactId=null,filename="",sourceUrl="",acquisitionMode="manual_file";
  if(systemCode==="qs_wur"){
   let fetched=await fetchQsStatic(editionYear);
   if(!fetched)fetched=await fetchQsRest(editionYear);
   if(fetched?.blocked)return json({ok:false,error:"QS publisher REST endpoint is Cloudflare-challenged from Pilot egress; no bypass attempted. Use authorised publisher file fallback or qualify an approved access route.",endpointAccessState:"cloudflare_challenge",status:fetched.status,systemCode,editionYear,nid:fetched.nid,workerVersion:VERSION},409);
   if(fetched&&fetched.rows?.length){
    rows=fetched.rows;sourceUrl=fetched.url;acquisitionMode=QS_STATIC[editionYear]?"publisher_static_xhr_json":"publisher_rest_json";
    const retained=sourceId?await retainJson(service,sourceId,systemCode,editionYear,sourceUrl,fetched.nid,fetched.bytes,rows.length,acquisitionMode):{hash:await sha(fetched.bytes),evidenceArtifactId:null,path:null};
    sourceHash=retained.hash;evidenceArtifactId=retained.evidenceArtifactId;filename=retained.path||"";
   }
  }
  if(!rows.length){
   const {data:imp,error:impErr}=await service.rpc("svc_ranking_latest_import",{p_system_code:systemCode,p_edition_year:editionYear});if(impErr)throw impErr;
   if(!imp?.storage_path)return json({ok:false,error:"authorised publisher file required; upload it in Administration → Sources & Imports, then revalidate this Layer 1 source",requiresPublisherFile:true,systemCode,editionYear,workerVersion:VERSION},409);
   const original=String(imp.original_filename||"");const isWorkbook=/\.(csv|xlsx)$/i.test(original),isTheJson=systemCode==="the_wur"&&/\.(json|txt)$/i.test(original);if(!isWorkbook&&!isTheJson)return json({ok:false,error:"Ranking parser accepts CSV/XLSX for QS/THE and native THE JSON/TXT exports. PDF/ZIP remain retained Evidence only.",requiresParserAdapter:true,systemCode,editionYear,filename:imp.original_filename,workerVersion:VERSION},422);
   const dl=await service.storage.from("evidence").download(imp.storage_path);if(dl.error||!dl.data)throw new Error(dl.error?.message||"publisher Evidence download failed");
   const bytes=new Uint8Array(await dl.data.arrayBuffer());rows=isTheJson?theRowsFromNativeJson(bytes,editionYear).rows:rowsFromWorkbook(bytes,editionYear,systemCode,original);sourceHash=imp.content_hash;evidenceArtifactId=imp.evidence_artifact_id;filename=imp.original_filename;sourceUrl=imp.source_url;acquisitionMode=isTheJson?"manual_the_native_json":"manual_file";
  }
  if(!rows.length)throw new Error("publisher source parsed zero ranking observations");
  const unknown=rows.filter(x=>x.rank_status==="unknown").length,indicatorCells=rows.reduce((n,r)=>n+Object.values(r.indicators||{}).filter(v=>v!==null).length,0);
  let reconciliationPreview=null;
  if(["qs_wur","the_wur"].includes(systemCode)){const {data:preview,error:previewErr}=await service.rpc("svc_ranking_reconciliation_preview_system",{p_rows:rows,p_country_code:"AU",p_system_code:systemCode});if(previewErr)throw previewErr;reconciliationPreview=preview;}
  if(mode!=="apply")return json({ok:true,mode:"dry_run",systemCode,editionYear,acquisitionMode,candidateObservations:rows.length,unknownRankSemantics:unknown,indicatorCells,sourceHash,evidenceArtifactId,filename,sourceUrl,reconciliationPreview,sample:rows.slice(0,5).map(({source_row_payload,...x})=>x),workerVersion:VERSION});
  if(!["manual_file","manual_the_native_json"].includes(acquisitionMode))return json({ok:false,error:"Direct QS JSON APPLY is intentionally disabled until the first dry-run and reuse/access review are accepted. Evidence has been retained; no ranking observations were written.",dryRunRequired:true,systemCode,editionYear,acquisitionMode,candidateObservations:rows.length,sourceHash,evidenceArtifactId,workerVersion:VERSION},409);
  const {data:applied,error:applyErr}=await service.rpc("svc_ranking_ingest_apply",{p_system_code:systemCode,p_edition_year:editionYear,p_source_url:sourceUrl,p_methodology_url:null,p_source_artifact_id:evidenceArtifactId,p_source_fingerprint:sourceHash,p_source_revision:"initial",p_rows:rows});if(applyErr)throw applyErr;
  return json({ok:true,mode:"apply",systemCode,editionYear,acquisitionMode,candidateObservations:rows.length,unknownRankSemantics:unknown,indicatorCells,sourceHash,evidenceArtifactId,filename,reconciliation:applied,workerVersion:VERSION});
 }catch(e){return json({ok:false,error:e instanceof Error?e.message:String(e),workerVersion:VERSION},500)}
});