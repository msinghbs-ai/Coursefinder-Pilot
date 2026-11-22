import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import * as XLSX from "npm:xlsx@0.18.5";

import { PUBLIC_SOURCES, USER_AGENT, attribution, isChallenge, qsRowsFromRestPages, robotsAllows, robotsRules, theRowsFromPublicJson } from "./public-readers.ts";

// v1.8.0 (CF-247 s966, Platform Admin 22 Nov 2026 09:22 AEDT, IR-005 / RM1J): THE and QS are attributed public rankings. THE is read from its public
// ranking JSON and QS from its public results endpoint with a plain GET (robots.txt and its crawl-delay honoured; no Firecrawl, no browser,
// no AI), applied and published with source attribution. No publisher file upload or terms hold. A challenge page is reported, never bypassed.
// v1.8.1 (CF-247 s968, 22 Nov 2026): the Australian reconciliation preview gets the Australian rows only. With every THE row (3,146) it passed the
// service role's 8 s statement limit; its answer covers Australia only, so it is unchanged.
// v1.8.2 (CF-247 s969): the apply batch size is the pipeline setting reading.ranking_apply_batch_rows (svc_worker_settings_v1), not a fixed 200.
// v1.8.3 (CF-247 s970): the reconciliation preview (a report) is not run for an apply, which matches rows itself; in a dry run a preview that
// passes the statement limit (its first call on a cold database can) is reported in the answer instead of failing the validation.
const VERSION="ranking-layer1-etl-v1.8.3";
const QS_STATIC:Record<number,string>={2026:"4061771"};
const QS_REST:Record<number,string>={2027:"4153156"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
const errText=(e:any,fallback="ranking operation failed")=>{if(e instanceof Error&&e.message)return e.message;if(e&&typeof e==="object"){for(const k of["message","error","details","detail","hint","code"]){const v=e[k];if(typeof v==="string"&&v.trim())return v}try{return JSON.stringify(e)}catch{}}return String(e||fallback)}
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

function rankingJsonRowsFromEvidence(bytes:Uint8Array,systemCode:string,expectedYear:number){
 const text=new TextDecoder().decode(bytes).replace(/^\uFEFF/,"").trim();
 // v1.6.1: THE native files start with a "Year NNNN" line; parse them with the THE reader, which also checks the declared year.
 if(systemCode==="the_wur"&&/^Year\s+\d{4}\s*[\r\n]/i.test(text)){const parsed=theRowsFromNativeJson(bytes,expectedYear);return{...parsed,scopeCountries:[...new Set(parsed.rows.map((r:any)=>r.country_text).filter(Boolean))]};}
 const root=JSON.parse(text);
 const payloads=Array.isArray(root)?root:Array.isArray(root?.responses)?root.responses:Array.isArray(root?.pages)?root.pages:root?.source==="manual_ranking_bundle"&&Array.isArray(root?.files)?root.files.map((x:any)=>x?.payload).filter(Boolean):[root];
 const raw:any[]=[];const countries=new Set<string>();
 if(systemCode==="qs_wur"){
  for(const payload of payloads){
   const d=payload?.data??payload;
   const y=Number(d?.edition_year??payload?.edition_year);if(Number.isInteger(y)&&y!==expectedYear)throw new Error("QS file edition mismatch");
   const rows=Array.isArray(d?.universities)?d.universities:[];raw.push(...rows);
  }
  const seen=new Set<string>();const rows=raw.map((r:any,i:number)=>{const parsed=parseRank(r.rank||r.rank_display||""),overall=scoreParts(r.overall_score);const indicators:any={};
   for(const it of Array.isArray(r.indicators)?r.indicators:[]){const k=key(it?.indicator_name||it?.indicator_id||("indicator_"+i));indicators[k]={label:clean(it?.indicator_name)||k,value_display:clean(it?.score)||null,value_numeric:score(it?.score),unit:"score",methodology_version:String(expectedYear),rank:clean(it?.rank)||null,group:clean(it?.group)||null};}
   const country=clean(r.country);if(country)countries.add(country);
   return{publisher_institution_id:clean(r.university_id||r.core_id)||null,institution_name:clean(r.name),profile_url:clean(r.profile_url)||null,country_text:country||null,location_text:[clean(r.city),country].filter(Boolean).join(", ")||null,
    rank_display:parsed.rank_display||null,rank_exact:parsed.rank_exact,rank_low:parsed.rank_low,rank_high:parsed.rank_high,is_tied:parsed.is_tied,rank_status:parsed.rank_status,
    overall_score:overall.numeric,overall_score_display:overall.display,overall_score_low:overall.low,overall_score_high:overall.high,source_row_ordinal:i+1,indicators,source_row_payload:r};
  }).filter((r:any)=>{if(!r.institution_name)return false;const k=(r.publisher_institution_id||key(r.institution_name))+"|"+(r.rank_display||"");if(seen.has(k))return false;seen.add(k);return true});
  if(!rows.length)throw new Error("QS JSON/TXT file contains no universities");
  return{rows,declaredYear:expectedYear,publisherStatus:"success",scopeCountries:[...countries]};
 }
 if(systemCode==="arwu"){
  for(const payload of payloads){const d=payload?.data??payload;const y=Number(d?.year??payload?.year);if(Number.isInteger(y)&&y!==expectedYear)throw new Error("ARWU file edition mismatch");const rows=Array.isArray(d?.rankings)?d.rankings:[];raw.push(...rows)}
  const seen=new Set<string>();const rows=raw.map((r:any,i:number)=>{const parsed=parseRank(r.rank||""),overall=scoreParts(r.score);const country=clean(r.country||r.region);if(country)countries.add(country);return{
   publisher_institution_id:clean(r.slug||r.id)||null,institution_name:clean(r.name),profile_url:clean(r.profile_url)||null,country_text:country||null,location_text:country||null,
   rank_display:parsed.rank_display||null,rank_exact:parsed.rank_exact,rank_low:parsed.rank_low,rank_high:parsed.rank_high,is_tied:parsed.is_tied,rank_status:parsed.rank_status,
   overall_score:overall.numeric,overall_score_display:overall.display,overall_score_low:overall.low,overall_score_high:overall.high,source_row_ordinal:i+1,
   indicators:{national_rank:{label:"National rank",value_display:clean(r.national_rank)||null,value_numeric:score(r.national_rank),unit:"rank",methodology_version:String(expectedYear)}},source_row_payload:r};
  }).filter((r:any)=>{if(!r.institution_name)return false;const k=(r.publisher_institution_id||key(r.institution_name))+"|"+(r.rank_display||"");if(seen.has(k))return false;seen.add(k);return true});
  if(!rows.length)throw new Error("ARWU JSON/TXT file contains no rankings");
  return{rows,declaredYear:expectedYear,publisherStatus:"success",scopeCountries:[...countries]};
 }
 if(systemCode==="the_wur"){
  for(const payload of payloads){const d=payload?.data??payload;const rows=Array.isArray(payload?.data?.data)?payload.data.data:(Array.isArray(d?.data)?d.data:[]);raw.push(...rows)}
  if(!raw.length)throw new Error("THE JSON/TXT file contains no ranking rows");
  const wrapped={status:"success",data:{data:raw}};const merged=new TextEncoder().encode(JSON.stringify(wrapped));
  const parsed=theRowsFromNativeJson(merged,expectedYear);for(const r of parsed.rows){if(r.country_text)countries.add(r.country_text)}
  return{...parsed,scopeCountries:[...countries]};
 }
 throw new Error("Unsupported ranking JSON/TXT system");
}

async function fetchQsStatic(year:number){
 const nid=QS_STATIC[year];if(!nid)return null;
 const url=`https://www.topuniversities.com/sites/default/files/qs-rankings-data/en/${nid}_indicators.txt`;
 const r=await fetch(url,{headers:{"User-Agent":"Mozilla/5.0","X-Requested-With":"XMLHttpRequest","Accept":"application/json","Referer":"https://www.topuniversities.com/world-university-rankings"}});
 if(!r.ok)throw new Error(`QS static XHR HTTP ${r.status}`);
 const text=await r.text(),bytes=new TextEncoder().encode(text);const payload=JSON.parse(text);if(!Array.isArray(payload?.data))throw new Error("QS static XHR payload missing data array");
 return{url,nid,bytes,text,payload,rows:qsRows(payload.data)};
}
const sleep=(ms:number)=>new Promise(r=>setTimeout(r,ms));
async function getPublic(url:string,accept="application/json"){
 const c=new AbortController(),t=setTimeout(()=>c.abort(),90000); // fixed: API time-out for one publisher request
 try{const r=await fetch(url,{signal:c.signal,redirect:"follow",headers:{"User-Agent":USER_AGENT,"Accept":accept}});const text=await r.text();return{status:r.status,contentType:r.headers.get("content-type"),text};}
 finally{clearTimeout(t)}
}
// robots.txt of the publisher: the path must be allowed for "User-agent: *"; its crawl-delay spaces the requests.
async function robotsFor(origin:string,target:string){
 const r=await getPublic(`${origin}/robots.txt`,"text/plain");
 const text=r.status===200?r.text:"",rules=robotsRules(text);
 if(!robotsAllows(text,target))throw new Error(`robots.txt of ${new URL(origin).hostname} does not allow ${new URL(target).pathname}`);
 return{delayMs:Math.max(0,Number(rules.crawlDelaySeconds||0))*1000};
}
const challenged=(system:string,url:string,status:number)=>({blocked:true,status,url,error:`${system} publisher endpoint returned a challenge page (HTTP ${status}); no bypass attempted. The edition held stays as it is; the source is temporarily unavailable and the Layer 1 run retries later.`});
async function fetchThePublic(year:number){
 const src=PUBLIC_SOURCES.the_wur,url=src.jsonUrl(year),robots=await robotsFor(src.origin,url);
 if(robots.delayMs)await sleep(robots.delayMs);
 const r=await getPublic(url);
 if(isChallenge(r.status,r.contentType,r.text))return challenged("THE",url,r.status);
 if(r.status!==200)throw new Error(`THE ranking JSON HTTP ${r.status}`);
 const payload=JSON.parse(r.text),parsed=theRowsFromPublicJson(payload,year),bytes=new TextEncoder().encode(r.text);
 return{url,pageUrl:src.pageUrl(year),nid:`the_wur_${year}`,bytes,rows:parsed.rows,stats:parsed.stats};
}
async function fetchQsRest(year:number){
 const nid=QS_REST[year];if(!nid)return null;
 const src=PUBLIC_SOURCES.qs_wur,base=`${src.origin}/rankings/endpoint?nid=${nid}&tab=indicators&items_per_page=500`,robots=await robotsFor(src.origin,base);
 const pages:any[]=[];let page=0,totalPages=1;
 while(page<totalPages){
  if(robots.delayMs)await sleep(robots.delayMs);
  const url=`${base}&page=${page}`,r=await getPublic(url);
  if(isChallenge(r.status,r.contentType,r.text))return challenged("QS",url,r.status);
  if(r.status!==200)throw new Error(`QS REST HTTP ${r.status}`);
  const d=JSON.parse(r.text);pages.push(d);totalPages=Math.max(1,Number(d?.total_pages)||1);page++;
 }
 const parsed=qsRowsFromRestPages(pages,year),text=JSON.stringify(pages),bytes=new TextEncoder().encode(text);
 return{url:`${src.origin}/rankings/endpoint?nid=${nid}`,pageUrl:src.pageUrl(year),nid,bytes,text,payload:pages,rows:parsed.rows,stats:parsed.stats};
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
  const body=await req.json().catch(()=>({})),systemCode=clean(body.system_code),editionYear=Number(body.edition_year),mode=clean(body.mode||"dry_run").toLowerCase(),sourceId=clean(body.source_id),importId=clean(body.import_id);
  if(!["qs_wur","the_wur","arwu"].includes(systemCode))throw new Error("unsupported ranking system");if(!Number.isInteger(editionYear))throw new Error("edition_year required");
  let rows:any[]=[],sourceHash="",evidenceArtifactId=null,filename="",sourceUrl="",acquisitionMode="manual_file";
  let imp:any=null;
  if(importId){
   const {data:ctx,error:ctxErr}=await service.rpc("svc_ranking_import_control_context",{p_import_id:importId});if(ctxErr)throw ctxErr;imp=ctx;
   if(!imp?.id||clean(imp.system_code)!==systemCode||Number(imp.edition_year)!==editionYear)throw new Error("selected ranking import does not match system/year");
  }
  let publicStats:any=null,jsonUrl="",publicSystem:""|"the_wur"|"qs_wur"="";
  if(!imp&&(systemCode==="qs_wur"||systemCode==="the_wur")){
   let fetched:any=systemCode==="qs_wur"?await fetchQsStatic(editionYear):null;
   if(!fetched)fetched=systemCode==="qs_wur"?await fetchQsRest(editionYear):await fetchThePublic(editionYear);
   if(fetched?.blocked)return json({ok:false,error:fetched.error,endpointAccessState:"challenge",status:fetched.status,url:fetched.url,systemCode,editionYear,workerVersion:VERSION},503);
   if(fetched&&fetched.rows?.length){
    rows=fetched.rows;jsonUrl=fetched.url;sourceUrl=fetched.pageUrl||fetched.url;publicStats=fetched.stats||null;
    acquisitionMode=systemCode==="the_wur"?"publisher_public_json":QS_STATIC[editionYear]?"publisher_static_xhr_json":"publisher_public_json";
    if(acquisitionMode==="publisher_public_json")publicSystem=systemCode;
    const retained=sourceId?await retainJson(service,sourceId,systemCode,editionYear,jsonUrl,fetched.nid,fetched.bytes,rows.length,acquisitionMode):{hash:await sha(fetched.bytes),evidenceArtifactId:null,path:null};
    sourceHash=retained.hash;evidenceArtifactId=retained.evidenceArtifactId;filename=retained.path||"";
   }
  }
  if(!rows.length){
   if(!imp){const latest=await service.rpc("svc_ranking_latest_import",{p_system_code:systemCode,p_edition_year:editionYear});if(latest.error)throw latest.error;imp=latest.data;}
   if(!imp?.storage_path)return json({ok:false,error:"ranking Evidence required; upload a publisher file in Administration → Sources & Imports",requiresPublisherFile:true,systemCode,editionYear,workerVersion:VERSION},409);
   const original=String(imp.original_filename||""),isWorkbook=/\.(csv|xlsx)$/i.test(original),isJsonText=/\.(json|txt)$/i.test(original);
   if(!isWorkbook&&!isJsonText)return json({ok:false,error:"Ranking parser accepts CSV/XLSX and governed JSON/TXT Evidence for QS, THE and ARWU.",requiresParserAdapter:true,systemCode,editionYear,filename:imp.original_filename,workerVersion:VERSION},422);
   const dl=await service.storage.from("evidence").download(imp.storage_path);if(dl.error||!dl.data)throw new Error(dl.error?.message||"publisher Evidence download failed");
   const bytes=new Uint8Array(await dl.data.arrayBuffer());
   if(isJsonText){const parsed=rankingJsonRowsFromEvidence(bytes,systemCode,editionYear);rows=parsed.rows;acquisitionMode="manual_file";}
   else {rows=rowsFromWorkbook(bytes,editionYear,systemCode,original);acquisitionMode="manual_file";}
   sourceHash=imp.content_hash;evidenceArtifactId=imp.evidence_artifact_id;filename=imp.original_filename;sourceUrl=imp.source_url;
  }
  if(!rows.length)throw new Error("publisher source parsed zero ranking observations");
  const unknown=rows.filter(x=>x.rank_status==="unknown").length,indicatorCells=rows.reduce((n,r)=>n+Object.values(r.indicators||{}).filter(v=>v!==null).length,0);
  let reconciliationPreview=null;
  if(["qs_wur","the_wur","arwu"].includes(systemCode)){if(mode!=="apply"){const previewRows=rows.filter((r:any)=>/^(australia|au|aus)$/i.test(clean(r.country_text)));const {data:preview,error:previewErr}=await service.rpc("svc_ranking_reconciliation_preview_system",{p_rows:previewRows,p_country_code:"AU",p_system_code:systemCode});reconciliationPreview=previewErr?{error:errText(previewErr),country_code:"AU",system_code:systemCode}:preview;}}
  if(mode!=="apply")return json({ok:true,mode:"dry_run",systemCode,editionYear,acquisitionMode,candidateObservations:rows.length,unknownRankSemantics:unknown,indicatorCells,sourceHash,evidenceArtifactId,filename,sourceUrl,jsonUrl:jsonUrl||null,publicStats,attribution:publicSystem?attribution(publicSystem,editionYear):null,reconciliationPreview,sample:rows.slice(0,5).map(({source_row_payload,...x})=>x),workerVersion:VERSION});
  // v1.8.0: public publisher JSON is applied like an uploaded file (Platform Admin 22 Nov 2026 09:22); its JSON is retained as evidence first.
  if(!["manual_file","manual_the_native_json","publisher_public_json","publisher_static_xhr_json"].includes(acquisitionMode))return json({ok:false,error:`acquisition mode ${acquisitionMode} cannot be applied`,systemCode,editionYear,acquisitionMode,workerVersion:VERSION},409);
  if(acquisitionMode!=="manual_file"&&!evidenceArtifactId)return json({ok:false,error:"apply of publisher JSON needs source_id so the JSON is retained as evidence first",systemCode,editionYear,acquisitionMode,workerVersion:VERSION},409);
  const revision=publicSystem?PUBLIC_SOURCES[publicSystem].revision:acquisitionMode==="publisher_static_xhr_json"?"qs_static_xhr_json_v1":"initial";
  const {data:ws,error:wsErr}=await service.rpc("svc_worker_settings_v1",{});if(wsErr)throw new Error(errText(wsErr));
  const batchSize=Math.floor(Number((ws||{})["reading.ranking_apply_batch_rows"]));if(!Number.isFinite(batchSize)||batchSize<1)throw new Error("pipeline setting reading.ranking_apply_batch_rows is missing");let appliedBatches=0,partialMapped=0,partialUnmapped=0;
  for(let offset=0;offset<rows.length;offset+=batchSize){
   const batch=rows.slice(offset,offset+batchSize);
   const {data:part,error:applyErr}=await service.rpc("svc_ranking_ingest_apply",{p_system_code:systemCode,p_edition_year:editionYear,p_source_url:sourceUrl,p_methodology_url:null,p_source_artifact_id:evidenceArtifactId,p_source_fingerprint:sourceHash,p_source_revision:revision,p_rows:batch});
   if(applyErr)throw new Error(errText(applyErr));
   appliedBatches++;partialMapped+=Number(part?.mapped||0);partialUnmapped+=Number(part?.unmapped||0);
  }
  const {data:finalized,error:finalizeErr}=await service.rpc("svc_ranking_ingest_finalize",{p_system_code:systemCode,p_edition_year:editionYear,p_source_artifact_id:evidenceArtifactId});
  if(finalizeErr)throw new Error(errText(finalizeErr));
  // v1.8.0: an attributed public edition is published live at once: access public, the attribution recorded, any other revision of the same
  // edition superseded, and the rows of AU, NZ and CA institutions not yet linked to a provider listed for review (Rankings › links).
  let published=null;
  if(publicSystem||acquisitionMode==="publisher_static_xhr_json"){const sys=(publicSystem||systemCode) as "the_wur"|"qs_wur";const {data:pub,error:pubErr}=await service.rpc("svc_ranking_public_edition_publish_v1",{p_system_code:systemCode,p_edition_year:editionYear,p_source_artifact_id:evidenceArtifactId,p_attribution:attribution(sys,editionYear)});if(pubErr)throw new Error(errText(pubErr));published=pub;}
  return json({ok:true,mode:"apply",systemCode,editionYear,acquisitionMode,candidateObservations:rows.length,unknownRankSemantics:unknown,indicatorCells,sourceHash,evidenceArtifactId,filename,sourceUrl,jsonUrl:jsonUrl||null,publicStats,reconciliation:{...finalized,mapped:Number(finalized?.mapped||0),unmapped:Number(finalized?.global_unmapped||0)},published,applyBatches:appliedBatches,batchSize,partialMapped,partialUnmapped,workerVersion:VERSION});
 }catch(e){return json({ok:false,error:errText(e),workerVersion:VERSION},500)}
});