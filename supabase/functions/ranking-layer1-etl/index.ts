import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import * as XLSX from "npm:xlsx@0.18.5";

const VERSION="ranking-layer1-etl-v1.0.0";
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
const clean=(v:unknown)=>String(v??"").replace(/^\uFEFF/,"").trim();
const key=(v:unknown)=>clean(v).toLowerCase().replace(/[^a-z0-9]+/g," ").trim();
function pick(row:Record<string,unknown>, aliases:string[]){const map=new Map(Object.entries(row).map(([k,v])=>[key(k),v]));for(const a of aliases){const v=map.get(key(a));if(v!==undefined&&clean(v)!=="")return clean(v)}return""}
function findRank(row:Record<string,unknown>,year:number){
 const direct=pick(row,["rank","world rank","ranking","rank "+year,"world university rank","world university ranking","world university rankings"]);if(direct)return direct;
 for(const [k,v] of Object.entries(row)){const kk=key(k);if((kk===String(year)||kk.includes(String(year)))&&/(rank|ranking|world)/.test(kk)&&clean(v))return clean(v)}
 return "";
}
function parseRank(raw:string){
 const display=clean(raw).replace(/^=/,"=");const norm=display.replace(/[–—]/g,"-").replace(/,/g,"").trim();
 if(!norm)return{rank_display:"",rank_exact:null,rank_low:null,rank_high:null,is_tied:false,rank_status:"unknown"};
 if(/reporter/i.test(norm))return{rank_display:display,rank_exact:null,rank_low:null,rank_high:null,is_tied:false,rank_status:"reporter"};
 if(/not\s*ranked|unranked|n\/a|^-$|^—$/i.test(norm))return{rank_display:display,rank_exact:null,rank_low:null,rank_high:null,is_tied:false,rank_status:"unranked"};
 const tied=/^=/.test(norm);const x=norm.replace(/^=/,"");
 const band=x.match(/^(\d+)\s*-\s*(\d+)$/);if(band)return{rank_display:display,rank_exact:null,rank_low:Number(band[1]),rank_high:Number(band[2]),is_tied:tied,rank_status:"ranked_band"};
 const plus=x.match(/^(\d+)\+$/);if(plus)return{rank_display:display,rank_exact:null,rank_low:Number(plus[1]),rank_high:null,is_tied:tied,rank_status:"ranked_band"};
 const exact=x.match(/^(\d+)$/);if(exact)return{rank_display:display,rank_exact:Number(exact[1]),rank_low:null,rank_high:null,is_tied:tied,rank_status:"ranked_exact"};
 return{rank_display:display,rank_exact:null,rank_low:null,rank_high:null,is_tied:tied,rank_status:"unknown"};
}
function score(raw:string){if(!raw)return null;const n=Number(raw.replace(/,/g,""));return Number.isFinite(n)?n:null}
function rowsFromWorkbook(bytes:Uint8Array,year:number){
 const wb=XLSX.read(bytes,{type:"array",cellDates:false,raw:false});let best:any[]=[];
 for(const name of wb.SheetNames){const rows=XLSX.utils.sheet_to_json<Record<string,unknown>>(wb.Sheets[name],{defval:"",raw:false});if(rows.length>best.length)best=rows}
 const out:any[]=[];let ordinal=0;
 for(const row of best){ordinal++;const institution=pick(row,["institution name","university","university name","name","institution"]);if(!institution)continue;
  const country=pick(row,["location","country territory","country/territory","country region","country/region","country"]);const rankRaw=findRank(row,year);const parsed=parseRank(rankRaw);
  const overall=pick(row,["overall score","overall","score"]);
  out.push({institution_name:institution,country_text:country||null,rank_display:parsed.rank_display||null,rank_exact:parsed.rank_exact,rank_low:parsed.rank_low,rank_high:parsed.rank_high,is_tied:parsed.is_tied,rank_status:parsed.rank_status,overall_score:score(overall),source_row_ordinal:ordinal,source_row_payload:row});
 }
 return out;
}

Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return json({error:"POST required",workerVersion:VERSION},405);
 const url=Deno.env.get("SUPABASE_URL")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
 if(!url||!serviceKey)return json({error:"service configuration missing",workerVersion:VERSION},500);
 const caller=req.headers.get("x-cf-layer1-service-key")||"";if(caller!==serviceKey)return json({error:"service authorization required",workerVersion:VERSION},403);
 const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 try{
  const body=await req.json().catch(()=>({}));const systemCode=clean(body.system_code);const editionYear=Number(body.edition_year);const mode=clean(body.mode||"dry_run").toLowerCase();
  if(!["qs_wur","the_wur"].includes(systemCode))throw new Error("unsupported ranking system");if(!Number.isInteger(editionYear))throw new Error("edition_year required");
  const {data:imp,error:impErr}=await service.rpc("svc_ranking_latest_import",{p_system_code:systemCode,p_edition_year:editionYear});if(impErr)throw impErr;
  if(!imp?.storage_path)return json({ok:false,error:"authorised publisher file required; upload it in Administration → Sources & Imports, then revalidate this Layer 1 source",requiresPublisherFile:true,systemCode,editionYear,workerVersion:VERSION},409);
  if(!/\.(csv|xlsx)$/i.test(String(imp.original_filename||"")))return json({ok:false,error:"Layer 1 ranking parser currently accepts CSV/XLSX publisher files; PDF/ZIP/JSON remain retained Evidence but require a dedicated adapter",requiresParserAdapter:true,systemCode,editionYear,filename:imp.original_filename,workerVersion:VERSION},422);
  const dl=await service.storage.from("evidence").download(imp.storage_path);if(dl.error||!dl.data)throw new Error(dl.error?.message||"publisher Evidence download failed");
  const bytes=new Uint8Array(await dl.data.arrayBuffer());const rows=rowsFromWorkbook(bytes,editionYear);if(!rows.length)throw new Error("publisher file parsed zero ranking observations; verify edition/file columns");
  const unknown=rows.filter(x=>x.rank_status==="unknown").length;
  if(mode!=="apply")return json({ok:true,mode:"dry_run",systemCode,editionYear,candidateObservations:rows.length,unknownRankSemantics:unknown,sourceHash:imp.content_hash,evidenceArtifactId:imp.evidence_artifact_id,filename:imp.original_filename,sample:rows.slice(0,5).map(({source_row_payload,...x})=>x),workerVersion:VERSION});
  const {data:applied,error:applyErr}=await service.rpc("svc_ranking_ingest_apply",{p_system_code:systemCode,p_edition_year:editionYear,p_source_url:imp.source_url,p_methodology_url:imp.methodology_url||null,p_source_artifact_id:imp.evidence_artifact_id,p_source_fingerprint:imp.content_hash,p_source_revision:imp.revision_note||"initial",p_rows:rows});
  if(applyErr)throw applyErr;
  return json({ok:true,mode:"apply",systemCode,editionYear,candidateObservations:rows.length,unknownRankSemantics:unknown,sourceHash:imp.content_hash,evidenceArtifactId:imp.evidence_artifact_id,filename:imp.original_filename,reconciliation:applied,workerVersion:VERSION});
 }catch(e){return json({ok:false,error:e instanceof Error?e.message:String(e),workerVersion:VERSION},500)}
});