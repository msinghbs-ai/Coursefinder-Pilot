import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import * as XLSX from "npm:xlsx@0.18.5";

const VERSION="ranking-qs-official-etl-v1.3.0";
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
const clean=(v:unknown)=>String(v??"").replace(/^\uFEFF/,"").trim();
const key=(v:unknown)=>clean(v).toLowerCase().replace(/[^a-z0-9]+/g," ").trim();
const score=(v:unknown)=>{const s=clean(v);if(!s||/^(?:-|—|n\/?a|null)$/i.test(s))return null;const n=Number(s.replace(/,/g,""));return Number.isFinite(n)&&n>=0&&n<=100?n:null};
const errText=(e:unknown)=>{if(e instanceof Error)return e.message;if(typeof e==="string")return e;try{const s=JSON.stringify(e);return s&&s!=="{}"?s:"unknown error"}catch{return"unknown error"}};

function parseRank(v:unknown){
 const display=clean(v).replace(/[–—]/g,"-");
 const tied=/^=/.test(display)||/=$/.test(display);
 const x=display.replace(/^=/,"").replace(/=$/,"").trim();
 let m=x.match(/^(\d+)\s*-\s*(\d+)$/);
 if(m)return{rank_display:(tied?"=":"")+x,rank_exact:null,rank_low:+m[1],rank_high:+m[2],is_tied:tied,rank_status:"ranked_band"};
 m=x.match(/^(\d+)\+$/);
 if(m)return{rank_display:(tied?"=":"")+x,rank_exact:null,rank_low:+m[1],rank_high:null,is_tied:tied,rank_status:"ranked_band"};
 m=x.match(/^(\d+)$/);
 if(m)return{rank_display:(tied?"=":"")+x,rank_exact:+m[1],rank_low:null,rank_high:null,is_tied:tied,rank_status:"ranked_exact"};
 return{rank_display:display||null,rank_exact:null,rank_low:null,rank_high:null,is_tied:tied,rank_status:display?"unknown":"unranked"};
}

function indicator(label:string,value:unknown,rank:unknown,year:number,group:string){
 const s=clean(value),pr=parseRank(rank);
 return{label,value_display:s&&score(value)!==null?s:null,value_numeric:score(value),unit:"score",methodology_version:String(year),group,...pr};
}

const idefs=[
 {code:"academic_reputation",label:"Academic Reputation",group:"Research & Discovery",aliases:["ar","academic reputation"]},
 {code:"employer_reputation",label:"Employer Reputation",group:"Employability",aliases:["er","employer reputation"]},
 {code:"faculty_student_ratio",label:"Faculty Student Ratio",group:"Learning Experience",aliases:["fsr","faculty student ratio","faculty student"]},
 {code:"citations_per_faculty",label:"Citations per Faculty",group:"Research & Discovery",aliases:["cpf","citations per faculty"]},
 {code:"international_faculty_ratio",label:"International Faculty Ratio",group:"Global Engagement",aliases:["ifr","international faculty ratio","international faculty"]},
 {code:"international_student_ratio",label:"International Student Ratio",group:"Global Engagement",aliases:["isr","international student ratio","international students"]},
 {code:"international_student_diversity",label:"International Student Diversity",group:"Global Engagement",aliases:["isd","international student diversity"]},
 {code:"international_research_network",label:"International Research Network",group:"Global Engagement",aliases:["irn","international research network"]},
 {code:"employment_outcomes",label:"Employment Outcomes",group:"Employability",aliases:["eo","ger","employment outcomes"]},
 {code:"sustainability",label:"Sustainability",group:"Sustainability",aliases:["sus","sustainability"]},
] as const;

function parseWorkbook(bytes:Uint8Array,year:number){
 const wb=XLSX.read(bytes,{type:"array",cellDates:false,raw:false});
 let best:any[][]=[];let sheetName="";
 for(const n of wb.SheetNames){const a=XLSX.utils.sheet_to_json<any[]>(wb.Sheets[n],{header:1,defval:"",raw:false});if(a.length>best.length){best=a;sheetName=n}}
 if(!best.length)throw new Error("QS workbook contains no rows");
 const title=best.slice(0,4).flat().map(clean).find(x=>/QS World University Rankings/i.test(x))||"";
 if(title&&!title.includes(String(year)))throw new Error(`QS workbook title does not match selected edition ${year}`);
 let hi=-1;
 for(let i=0;i<Math.min(8,best.length);i++){
  const ks=best[i].map(key);
  if((ks.includes("name")||ks.includes("institution"))&&(ks.includes("rank")||ks.includes("rank display"))&&ks.includes("overall score")){hi=i;break}
 }
 if(hi<0)throw new Error("Official QS workbook header row not found");
 const headers=best[hi].map(key);
 const pos=(...names:string[])=>{for(const n of names){const i=headers.indexOf(key(n));if(i>=0)return i}return-1};
 const nameI=pos("name","institution"),rankI=pos("rank","rank display"),prevI=pos("previous rank","rank display2"),countryI=pos("country territory","location"),regionI=pos("region"),overallI=pos("overall score");
 if([nameI,rankI,countryI,overallI].some(i=>i<0))throw new Error("Official QS workbook required columns missing");
 const rows:any[]=[];
 for(let ri=hi+1;ri<best.length;ri++){
  const r=best[ri],name=clean(r[nameI]);if(!name)continue;
  const pr=parseRank(r[rankI]);const inds:any={};
  for(const def of idefs){const scoreNames=def.aliases.flatMap(a=>[`${a} score`,a]),rankNames=def.aliases.map(a=>`${a} rank`),si=pos(...scoreNames),rki=pos(...rankNames);if(si>=0||rki>=0)inds[def.code]=indicator(def.label,si>=0?r[si]:null,rki>=0?r[rki]:null,year,def.group)}
  const source:any={};headers.forEach((h,i)=>{if(h&&clean(r[i]))source[h]=r[i]});
  rows.push({publisher_institution_id:clean(source["publisher id"]||source["nid"]||source["university id"])||null,institution_name:name,profile_url:clean(source["profile url"])||null,country_text:clean(r[countryI])||null,location_text:[clean(r[countryI]),regionI>=0?clean(r[regionI]):""].filter(Boolean).join(" · ")||null,...pr,overall_score:score(r[overallI]),overall_score_display:score(r[overallI])!==null?clean(r[overallI])||null:null,overall_score_low:null,overall_score_high:null,source_row_ordinal:rows.length+1,indicators:inds,source_row_payload:{...source,previous_rank:prevI>=0?clean(r[prevI])||null:null,qs_official_workbook:true}});
 }
 const counts=new Map<number,number>();
 for(const r of rows)if(r.rank_exact!=null)counts.set(r.rank_exact,(counts.get(r.rank_exact)||0)+1);
 for(const r of rows)if(r.rank_exact!=null&&(counts.get(r.rank_exact)||0)>1){r.is_tied=true;if(!String(r.rank_display||"").startsWith("="))r.rank_display="="+r.rank_display}
 if(rows.length<1000)throw new Error(`QS World workbook parsed only ${rows.length} rows; global edition requires at least 1000`);
 const unknown=rows.filter(r=>r.rank_status==="unknown").length;
 if(unknown>10)throw new Error(`QS workbook has ${unknown} unknown rank semantics`);
 return{rows,sheetName,headerRow:hi+1,title};
}

function decodeBase64(value:string){
 const bin=atob(value),out=new Uint8Array(bin.length);
 for(let i=0;i<bin.length;i++)out[i]=bin.charCodeAt(i);
 return out;
}

async function gunzipBase64(value:string){
 const compressed=decodeBase64(value);
 const stream=new Blob([compressed]).stream().pipeThrough(new DecompressionStream("gzip"));
 return new Uint8Array(await new Response(stream).arrayBuffer());
}

async function loadEvidenceBytes(svc:any,imp:any){
 const path=clean(imp.storage_path);
 if(path.startsWith("inline://")){
  const payload=clean(imp.inline_payload_gzip_base64);
  if(!payload)throw new Error("QS inline Evidence payload is not retained for this import; re-register the authorised publisher XLSX Evidence");
  try{return await gunzipBase64(payload)}catch(e){throw new Error(`QS inline Evidence decode failed: ${errText(e)}`)}
 }
 const dl=await svc.storage.from("evidence").download(path);
 if(dl.error||!dl.data)throw new Error(`QS Evidence download failed: ${errText(dl.error||"empty object")}`);
 return new Uint8Array(await dl.data.arrayBuffer());
}

Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return json({error:"POST required",workerVersion:VERSION},405);
 const url=Deno.env.get("SUPABASE_URL")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
 if(!url||!serviceKey)return json({error:"service configuration missing",workerVersion:VERSION},500);
 if((req.headers.get("x-cf-layer1-service-key")||"")!==serviceKey)return json({error:"service authorization required",workerVersion:VERSION},403);
 const svc=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 try{
  const body=await req.json(),year=Number(body.edition_year),mode=clean(body.mode||"dry_run"),importId=clean(body.import_id);
  if(!Number.isInteger(year)||!importId)throw new Error("edition_year and import_id required");
  const{data:imp,error:ie}=await svc.rpc("svc_ranking_import_control_context",{p_import_id:importId});
  if(ie)throw new Error(`QS import context failed: ${errText(ie)}`);
  if(!imp?.id||imp.system_code!=="qs_wur"||Number(imp.edition_year)!==year)throw new Error("selected import is not the requested QS edition");
  if(!/\.xlsx$/i.test(String(imp.original_filename||"")))throw new Error("QS World manual import requires the official/generated QS XLSX workbook");
  const bytes=await loadEvidenceBytes(svc,imp),parsed=parseWorkbook(bytes,year),rows=parsed.rows,indicatorCells=rows.reduce((n,r)=>n+Object.keys(r.indicators||{}).length,0);
  const{data:preview,error:pe}=await svc.rpc("svc_ranking_reconciliation_preview_system",{p_rows:rows,p_country_code:"AU",p_system_code:"qs_wur"});
  if(pe)throw new Error(`QS reconciliation preview failed: ${errText(pe)}`);
  const base={ok:true,mode:mode==="apply"?"apply":"dry_run",systemCode:"qs_wur",editionYear:year,acquisitionMode:"qs_xlsx_evidence",evidenceTransport:clean(imp.storage_path).startsWith("inline://")?"postgres_inline_gzip":"storage",candidateObservations:rows.length,unknownRankSemantics:rows.filter(r=>r.rank_status==="unknown").length,indicatorCells,sourceHash:imp.content_hash,evidenceArtifactId:imp.evidence_artifact_id,filename:imp.original_filename,sourceUrl:imp.source_url,reconciliationPreview:preview,workbook:{sheet:parsed.sheetName,header_row:parsed.headerRow,title:parsed.title},sample:rows.slice(0,5).map(({source_row_payload,...x})=>x),workerVersion:VERSION};
  if(mode!=="apply")return json(base);
  let mapped=0,unmapped=0,batches=0;
  for(let i=0;i<rows.length;i+=200){
   const{data:p,error:e}=await svc.rpc("svc_ranking_ingest_apply",{p_system_code:"qs_wur",p_edition_year:year,p_source_url:imp.source_url,p_methodology_url:imp.methodology_url||null,p_source_artifact_id:imp.evidence_artifact_id,p_source_fingerprint:imp.content_hash,p_source_revision:"qs_xlsx_evidence_v1",p_rows:rows.slice(i,i+200)});
   if(e)throw new Error(`QS apply batch ${batches+1} failed: ${errText(e)}`);
   mapped+=Number(p?.mapped||0);unmapped+=Number(p?.unmapped||0);batches++;
  }
  const{data:finalized,error:fe}=await svc.rpc("svc_ranking_ingest_finalize",{p_system_code:"qs_wur",p_edition_year:year,p_source_artifact_id:imp.evidence_artifact_id});
  if(fe)throw new Error(`QS finalize failed: ${errText(fe)}`);
  return json({...base,reconciliation:finalized,applyBatches:batches,batchSize:200,partialMapped:mapped,partialUnmapped:unmapped});
 }catch(e){return json({ok:false,error:errText(e),workerVersion:VERSION},422)}
});
