import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const VERSION = "scholarships-au-etl-v0.1.1";
const STUDY_SEARCH = "https://search.studyaustralia.gov.au/scholarships";
const DFAT_AWARDS = "https://www.dfat.gov.au/people-to-people/australia-awards/australia-awards-scholarships";
const DFAT_DATES = "https://www.dfat.gov.au/people-to-people/australia-awards/australia-awards-scholarships-opening-and-closing-dates";
const DFAT_HANDBOOK_PAGE = "https://www.dfat.gov.au/about-us/publications/australia-awards-scholarships-policy-handbook";
const DFAT_HANDBOOK_PDF = "https://www.dfat.gov.au/sites/default/files/aus-awards-scholarships-policy-handbook.pdf";
const OASIS = "https://oasis.dfat.gov.au/";

const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json", "cache-control": "no-store" },
});
const clean = (v: unknown) => String(v ?? "").replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();

function decodeHtml(s: string) {
  const named: Record<string, string> = { amp:"&",lt:"<",gt:">",quot:'"',apos:"'",nbsp:" ",ndash:"–",mdash:"—" };
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_m,h) => String.fromCodePoint(parseInt(h,16)))
    .replace(/&#(\d+);/g, (_m,d) => String.fromCodePoint(parseInt(d,10)))
    .replace(/&([a-z]+);/gi, (m,n) => named[n.toLowerCase()] ?? m);
}
function htmlLines(html: string) {
  const text = html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi," ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi," ")
    .replace(/<(?:br\s*\/?>|\/p>|\/div>|\/li>|\/h[1-6]>|\/section>|\/article>)/gi,"\n")
    .replace(/<[^>]+>/g," ");
  return decodeHtml(text).split(/\r?\n/).map(clean).filter(Boolean);
}
const htmlText = (html:string) => clean(htmlLines(html).join(" "));
function extractH1(html:string) {
  const m=html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i);
  return m ? clean(decodeHtml(m[1].replace(/<[^>]+>/g," "))) : "";
}
function absolute(base:string, href:string) { try { return new URL(href,base).toString(); } catch { return href; } }

async function rpc(client:any,name:string,args:Record<string,unknown>={}) {
  const {data,error}=await client.rpc(name,args);
  if(error) throw new Error(`${name}: ${error.message}`);
  return data;
}
async function sha256(bytes:Uint8Array) {
  const hash=await crypto.subtle.digest("SHA-256",bytes);
  return [...new Uint8Array(hash)].map(b=>b.toString(16).padStart(2,"0")).join("");
}
async function fetchBytes(url:string) {
  const res=await fetch(url,{redirect:"follow",headers:{"user-agent":"CourseFinder-Pilot/Scholarships-0.1.1"}});
  if(!res.ok) throw new Error(`source HTTP ${res.status}: ${url}`);
  const bytes=new Uint8Array(await res.arrayBuffer());
  return {url:res.url,bytes,hash:await sha256(bytes),contentType:res.headers.get("content-type")||"application/octet-stream"};
}
async function fetchHtml(url:string) {
  const r=await fetchBytes(url);
  return {...r,html:new TextDecoder("utf-8").decode(r.bytes)};
}

function parseProviderLink(detailUrl:string,html:string) {
  const re=/href\s*=\s*["']([^"']*\/provider\/[^"']+\/([0-9a-f]{32})(?:\/[^"']*)?)["'][^>]*>([\s\S]*?)<\/a>/ig;
  let m:RegExpExecArray|null;
  while((m=re.exec(html))) {
    const name=clean(decodeHtml(m[3].replace(/<[^>]+>/g," ")));
    if(name && !/view (?:courses|scholarships)/i.test(name)) return {url:absolute(detailUrl,m[1]),id:m[2].toLowerCase(),name};
  }
  return null;
}
function parseCricos(html:string) {
  return htmlText(html).match(/CRICOS\s*CODE\s*:\s*([0-9]{5}[A-Z])/i)?.[1]?.toUpperCase() || null;
}
const months:Record<string,number>={january:1,february:2,march:3,april:4,may:5,june:6,july:7,august:8,september:9,october:10,november:11,december:12};
function parseDateOnly(s:string) {
  const m=s.match(/(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)?\s*,?\s*(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(20\d{2})/i);
  if(!m) return null;
  const d=Number(m[1]),mo=months[m[2].toLowerCase()],y=Number(m[3]);
  if(!mo||d<1||d>31) return null;
  return `${y}-${String(mo).padStart(2,"0")}-${String(d).padStart(2,"0")}`;
}
function infoValue(lines:string[],label:string) {
  const p=label.toLowerCase()+":";
  const line=lines.find(x=>x.toLowerCase().startsWith(p));
  return line?clean(line.slice(p.length)):null;
}
function discoverStudyLinks(base:string,html:string) {
  const re=/href\s*=\s*["']([^"']*\/scholarship\/[^"']+\/[0-9a-f]{32}(?:\?[^"']*)?)["']/ig;
  const out:string[]=[],seen=new Set<string>(); let m:RegExpExecArray|null;
  while((m=re.exec(html))) { const u=absolute(base,m[1]).replace(/\?.*$/,''); if(!seen.has(u)){seen.add(u);out.push(u);} }
  return out;
}

function parseStudyAustraliaDetail(detailUrl:string,html:string,provider:any,providerHtml:string|null) {
  const id=detailUrl.match(/\/([0-9a-f]{32})(?:\/?(?:\?.*)?)$/i)?.[1]?.toLowerCase();
  if(!id) throw new Error(`Study Australia scholarship identifier missing in ${detailUrl}`);
  const name=extractH1(html); if(!name) throw new Error(`Study Australia scholarship title missing for ${id}`);
  const lines=htmlLines(html);
  const awardText=infoValue(lines,"Award value"),levelText=infoValue(lines,"Level of study"),closingText=infoValue(lines,"Closing date");
  const infoIdx=lines.findIndex(x=>/^Scholarship Information$/i.test(x));
  const eligIdx=lines.findIndex(x=>/^Eligibility Requirements$/i.test(x));
  const body=lines.slice(infoIdx>=0?infoIdx+1:0,eligIdx>infoIdx?eligIdx:lines.length)
    .filter(x=>!/^(Award value|Level of study|Closing date)\s*:/i.test(x)).filter(x=>x.length>25);
  const description=body.sort((a,b)=>b.length-a.length)[0]||null;
  const closeDate=closingText?parseDateOnly(closingText):null;
  const titleYear=name.match(/\b(20\d{2})\b/)?.[1]||null;
  const academicYear=closeDate?Number(closeDate.slice(0,4)):(titleYear?Number(titleYear):null);
  const recurring=!!closingText&&/each year|annual|annually|every year/i.test(closingText);
  const cycleCode=academicYear?String(academicYear):(recurring?"recurring":"current");
  const cycleStatus=closeDate&&closeDate<new Date().toISOString().slice(0,10)?"closed":"active";
  const cricos=providerHtml?parseCricos(providerHtml):null;
  const scopes=cricos?[{scope_key:`provider:${cricos}`,scope_type:"provider",target_code:cricos,include_exclude:"include"}]:[];
  const windows=closingText?[{window_key:"primary",round_code:null,label:"Published closing window",opens_at:null,closes_at:null,application_method:"provider",application_url:detailUrl,status:closeDate?cycleStatus:"unknown",metadata:{source_closing_text:closingText,source_closing_date:closeDate,source_granularity:closeDate?"date":"text"}}]:[];

  const awardTiers:any[]=[],coverage:any[]=[];
  if(awardText){
    const a=awardText.match(/(?:AUD\s*)?\$\s*([\d,]+(?:\.\d+)?)/i);
    if(a) awardTiers.push({tier_code:"published_award",label:"Published award",amount:Number(a[1].replace(/,/g,"")),currency_code:"AUD",percentage:null,basis:/annually|annual|per year/i.test(awardText)?"annual":"published",notes:awardText,display_order:10});
  }
  // Percent is punctuation, so a trailing word-boundary after '%' is incorrect. Accept whitespace/punctuation/end-of-string explicitly.
  const pct=(description||"").match(/\b(\d{1,3}(?:\.\d+)?)\s*%(?=\s|[.,;:)]|$)/);
  if(pct&&/fee|tuition/i.test(description||"")){
    const p=Number(pct[1]);
    awardTiers.push({tier_code:"published_fee_reduction",label:"Published fee reduction",amount:null,currency_code:null,percentage:p,basis:"tuition_fee_reduction",notes:description,display_order:20});
    coverage.push({coverage_key:"tuition_fee_reduction",coverage_type:"tuition_fees",percentage:p,amount:null,currency_code:null,duration_value:null,duration_unit:null,notes:description});
  }
  const groupCode=`${cycleCode}:published_eligibility`;
  const criteria=description?[{criterion_key:"published_narrative",group_code:groupCode,criterion_type:"published_eligibility_narrative",operator:"source_text",value_text:null,value_number:null,value_codes:null,value_json:{source_level_of_study:levelText,source_description:description},human_text:description,is_mandatory:true,machine_evaluable:false,status:"active",confidence:"0.90"}]:[];
  return {record:{source_record_id:id,identifier_scheme:"study_australia_scholarship_id",name,scholarship_type:"provider_scholarship",description,audience:"international",award_value_text:awardText||(pct?`${pct[1]}%`:null),application_required:true,application_open_date:null,application_close_date:closeDate,academic_year:academicYear,source_url:detailUrl,confidence:"1.00",provider_cricos:cricos,source_provider_id:provider?.id||null,source_provider_name:provider?.name||null,cycles:[{cycle_code:cycleCode,academic_year:academicYear,intake_label:academicYear?String(academicYear):(recurring?"Recurring source cycle":"Current source cycle"),valid_from:null,valid_to:closeDate,status:cycleStatus,metadata:{source_level_of_study:levelText,source_closing_text:closingText,source_record_url:detailUrl,source_provider_id:provider?.id||null,source_provider_cricos:cricos},windows,scopes,criterion_groups:description?[{group_code:groupCode,label:"Published eligibility narrative",conjunction:"all",is_mandatory:true,display_order:10}]:[],criteria,award_tiers:awardTiers,coverage}]}};
}
function validateRecord(r:any){
  if(!r?.source_record_id||!r?.name||!Array.isArray(r?.cycles)||!r.cycles.length) throw new Error("invalid scholarship record shape");
  for(const c of r.cycles){
    if(!c?.cycle_code) throw new Error(`cycle_code missing for ${r.source_record_id}`);
    for(const w of c.windows||[]) if(!w?.window_key) throw new Error(`window_key missing for ${r.source_record_id}`);
    for(const s of c.scopes||[]) if(!s?.scope_key||!s?.scope_type) throw new Error(`scope invalid for ${r.source_record_id}`);
    for(const g of c.criterion_groups||[]) if(!g?.group_code) throw new Error(`criterion group invalid for ${r.source_record_id}`);
    for(const x of c.criteria||[]) if(!x?.criterion_key||!x?.criterion_type) throw new Error(`criterion invalid for ${r.source_record_id}`);
    for(const t of c.award_tiers||[]) if(!t?.tier_code) throw new Error(`award tier invalid for ${r.source_record_id}`);
    for(const x of c.coverage||[]) if(!x?.coverage_key||!x?.coverage_type) throw new Error(`coverage invalid for ${r.source_record_id}`);
  }
}
async function buildStudyAustralia(body:any){
  const maxRecords=Math.max(1,Math.min(Number(body?.max_records||10),50));
  let urls:string[]=Array.isArray(body?.urls)?body.urls.map(clean).filter(Boolean):[];
  if(!urls.length){
    const start=Math.max(1,Number(body?.page_start||1)),end=Math.max(start,Math.min(Number(body?.page_end||start),start+9));
    for(let p=start;p<=end&&urls.length<maxRecords;p++){
      const page=await fetchHtml(`${STUDY_SEARCH}?page=${p}`);
      for(const u of discoverStudyLinks(page.url,page.html)) if(!urls.includes(u)) urls.push(u);
    }
  }
  urls=urls.slice(0,maxRecords); if(!urls.length) throw new Error("Study Australia discovery returned no scholarship detail URLs");
  const parsed:any[]=[];
  for(const url of urls){
    const detail=await fetchHtml(url),provider=parseProviderLink(detail.url,detail.html),providerPage=provider?await fetchHtml(provider.url):null;
    const out=parseStudyAustraliaDetail(detail.url,detail.html,provider,providerPage?.html||null); validateRecord(out.record);
    parsed.push({...out,evidenceParts:[{name:"scholarship-detail",url:detail.url,bytes:detail.bytes,hash:detail.hash,contentType:detail.contentType},...(providerPage?[{name:"provider-detail",url:providerPage.url,bytes:providerPage.bytes,hash:providerPage.hash,contentType:providerPage.contentType}]:[])]});
  }
  return parsed;
}

const AAS_MAIN_COUNTRIES=["Algeria","Angola","Bangladesh","Bhutan","Botswana","Cambodia","Côte d'Ivoire","Democratic Republic of the Congo","Egypt","Ethiopia","Federated States of Micronesia","Fiji","Ghana","Guinea","The Gambia","Indonesia","Kiribati","Kenya","Laos","Madagascar","Malawi","Maldives","Marshall Islands","Mauritius","Mongolia","Morocco","Mozambique","Myanmar","Namibia","Nepal","New Caledonia","Nigeria","Niue","Pakistan","Papua New Guinea","Philippines","Rwanda","Samoa","Sierra Leone","Solomon Islands","South Africa","Sri Lanka","Tanzania","Thailand","Timor-Leste","Tonga","Tuvalu","Uganda","Vanuatu","Vietnam","Wallis and Futuna","Zambia","Zimbabwe"];
async function buildAustraliaAwards(){
  const [awards,dates,handbookPage,handbookPdf,oasis]=await Promise.all([fetchHtml(DFAT_AWARDS),fetchHtml(DFAT_DATES),fetchHtml(DFAT_HANDBOOK_PAGE),fetchBytes(DFAT_HANDBOOK_PDF),fetchHtml(OASIS)]);
  const at=htmlText(awards.html),dt=htmlText(dates.html),ht=htmlText(handbookPage.html),ot=htmlText(oasis.html);
  if(!/full tuition fees/i.test(at)||!/Overseas Student Health Cover/i.test(at)) throw new Error("DFAT Australia Awards benefits source markers missing");
  if(!/Dates for study commencing in 2027/i.test(dt)||!/1 February 2026/i.test(dt)||!/30 April 2026/i.test(dt)) throw new Error("DFAT 2027 application date markers missing");
  if(!/Updated June 2026/i.test(ht)) throw new Error("DFAT handbook version marker missing");
  if(new TextDecoder("ascii").decode(handbookPdf.bytes.slice(0,5))!=="%PDF-") throw new Error("DFAT handbook PDF marker missing");
  if(!/AAS\s*2027/i.test(ot)&&!/Australia Awards Scholarships/i.test(ot)) throw new Error("OASIS AAS source marker missing");
  const cycle="2027",root=`${cycle}:eligibility_all`,country=`${cycle}:country_any`;
  const record={source_record_id:"AAS",identifier_scheme:"dfat_award_scheme",name:"Australia Awards Scholarships",scholarship_type:"government_scholarship",description:"Long-term Australian Government scholarships for citizens of participating countries to undertake full-time study at participating Australian institutions.",audience:"international",award_value_text:"Full scholarship benefits as published by DFAT",application_required:true,application_open_date:"2026-02-01",application_close_date:"2026-06-30",academic_year:2027,source_url:DFAT_AWARDS,confidence:"1.00",provider_cricos:null,source_provider_id:null,source_provider_name:"Department of Foreign Affairs and Trade",cycles:[{cycle_code:cycle,academic_year:2027,intake_label:"Study commencing in 2027",valid_from:"2026-02-01",valid_to:"2026-06-30",status:"closed",metadata:{scheme_code:"AAS",oasis_label:"AAS 2027",handbook_version:"June 2026",country_specific_profiles_required:true},windows:[{window_key:"main",round_code:"AAS-2027-MAIN",label:"2027 main application round",opens_at:"2026-02-01T09:00:00+11:00",closes_at:"2026-04-30T14:00:00+10:00",application_method:"OASIS_or_country_profile",application_url:OASIS,status:"closed",metadata:{source_timezone_open:"AEDT",source_timezone_close:"AEST",eligible_country_group:"main AAS 2027 list"}},{window_key:"palau",round_code:"AAS-2027-PLW",label:"2027 Palau application round",opens_at:"2026-03-30T09:00:00+11:00",closes_at:"2026-06-30T14:00:00+10:00",application_method:"country_profile",application_url:DFAT_DATES,status:"closed",metadata:{source_timezone_open:"AEDT",source_timezone_close:"AEST",eligible_country:"Palau"}}],scopes:[],criterion_groups:[{group_code:root,label:"General eligibility",conjunction:"all",is_mandatory:true,display_order:10},{group_code:country,parent_group_code:root,label:"Participating-country pathway",conjunction:"any",is_mandatory:true,display_order:20}],criteria:[{criterion_key:"country_main",group_code:country,criterion_type:"citizenship_and_residency",operator:"in_source_list",value_json:{countries:AAS_MAIN_COUNTRIES},human_text:"Be a citizen of a participating AAS 2027 country and meet the applicable country-profile residence/application requirements.",is_mandatory:true,machine_evaluable:false,status:"active",confidence:"1.00"},{criterion_key:"country_palau",group_code:country,criterion_type:"citizenship_and_residency",operator:"equals_source_country",value_text:"Palau",human_text:"Palau applicants use the separately published 30 March to 30 June 2026 application round.",is_mandatory:true,machine_evaluable:false,status:"active",confidence:"1.00"},{criterion_key:"age",group_code:root,criterion_type:"minimum_age",operator:">=",value_number:18,human_text:"Be at least 18 years of age on 1 February of the year of commencing the scholarship.",is_mandatory:true,machine_evaluable:true,status:"active",confidence:"1.00"},{criterion_key:"no_au_status",group_code:root,criterion_type:"citizenship_residency_restriction",operator:"not",value_text:"Australian citizen or permanent resident",human_text:"Must not be an Australian citizen, hold permanent residency in Australia, or be applying to live permanently in Australia.",is_mandatory:true,machine_evaluable:false,status:"active",confidence:"1.00"},{criterion_key:"not_military",group_code:root,criterion_type:"employment_status",operator:"not",value_text:"current serving military personnel",human_text:"Must not be current serving military personnel.",is_mandatory:true,machine_evaluable:false,status:"active",confidence:"1.00"},{criterion_key:"prior_award_interval",group_code:root,criterion_type:"prior_award_interval",operator:">=",value_number:4,value_text:"years outside Australia",human_text:"Applicants who previously received a long-term Australia Award must satisfy the handbook's four-year outside-Australia condition before reapplying.",is_mandatory:true,machine_evaluable:false,status:"active",confidence:"1.00"},{criterion_key:"institution_admission",group_code:root,criterion_type:"institution_admission",operator:"satisfy",human_text:"Must be able to satisfy the admission requirements of the institution at which the award is to be undertaken.",is_mandatory:true,machine_evaluable:false,status:"active",confidence:"1.00"},{criterion_key:"student_visa",group_code:root,criterion_type:"visa_requirement",operator:"satisfy",human_text:"Must be able to satisfy all requirements of the Department of Home Affairs to hold a Student Visa.",is_mandatory:true,machine_evaluable:false,status:"active",confidence:"1.00"},{criterion_key:"no_overlapping_award",group_code:root,criterion_type:"funding_exclusivity",operator:"not",value_text:"overlapping scholarship or financial award",human_text:"Must disclose and not hold another scholarship or financial award that overlaps with the Australia Awards Scholarship, subject to handbook rules.",is_mandatory:true,machine_evaluable:false,status:"active",confidence:"1.00"}],award_tiers:[],coverage:[{coverage_key:"tuition",coverage_type:"tuition_fees",percentage:100,notes:"Full tuition fees."},{coverage_key:"return_air_travel",coverage_type:"return_air_travel",notes:"Single return economy-class airfare via the most direct route, subject to DFAT policy."},{coverage_key:"establishment",coverage_type:"establishment_allowance",notes:"Once-only establishment allowance contribution."},{coverage_key:"living",coverage_type:"living_expenses",notes:"Contribution to Living Expenses paid at the rate determined by DFAT."},{coverage_key:"iap",coverage_type:"introductory_academic_program",notes:"Compulsory Introductory Academic Program before formal study."},{coverage_key:"oshc",coverage_type:"overseas_student_health_cover",notes:"OSHC for the duration of the award for the award holder, subject to policy conditions."},{coverage_key:"pce",coverage_type:"pre_course_english",notes:"Pre-course English may be available if deemed necessary."},{coverage_key:"academic_support",coverage_type:"supplementary_academic_support",notes:"Supplementary academic support may be available where approved."},{coverage_key:"fieldwork",coverage_type:"fieldwork_travel",notes:"Eligible research fieldwork support may be available subject to policy conditions."}]}]};
  validateRecord(record);
  return {record,parts:[{name:"awards",...awards},{name:"dates",...dates},{name:"handbook-page",...handbookPage},{name:"handbook",...handbookPdf},{name:"oasis",...oasis}].map((x:any)=>({name:x.name,url:x.url,bytes:x.bytes,hash:x.hash,contentType:x.contentType}))};
}

async function prepareSource(client:any,feed:string){
  return feed==="study_australia"?rpc(client,"svc_scholarship_prepare_source",{p_source_key:"au_study_australia_scholarships",p_label:"Study Australia Scholarship Search",p_url:STUDY_SEARCH,p_source_type:"scholarship_catalogue",p_trust_rank:95,p_metadata:{publisher:"Australian Trade and Investment Commission",authority_class:"official_government_search",source_identifier_scheme:"study_australia_scholarship_id",provider_mapping:"provider_source_id_to_provider_page_cricos_to_exact_canonical_cricos"}}):rpc(client,"svc_scholarship_prepare_source",{p_source_key:"au_dfat_australia_awards",p_label:"DFAT Australia Awards Scholarships",p_url:DFAT_AWARDS,p_source_type:"government_scholarship_program",p_trust_rank:100,p_metadata:{publisher:"Department of Foreign Affairs and Trade",authority_class:"official_government_program",source_identifier_scheme:"dfat_award_scheme",handbook_version:"June 2026"}});
}
async function registerBundle(client:any,sourceId:string,recordPath:string,sourceUrl:string,parts:any[]){
  const components:any[]=[];
  for(const p of parts){
    const baseType=p.contentType.split(";")[0],ext=baseType.includes("pdf")?"pdf":baseType.includes("html")?"html":"bin",path=`layer2a/AU/scholarships/${recordPath}/${p.name}-${p.hash}.${ext}`;
    const up=await client.storage.from("evidence").upload(path,p.bytes,{contentType:baseType,upsert:true}); if(up.error) throw up.error;
    const evidenceId=await rpc(client,"svc_scholarship_register_evidence",{p_source_id:sourceId,p_source_url:p.url,p_storage_path:path,p_content_hash:p.hash,p_mime_type:baseType,p_metadata:{component:p.name,source_record_id:recordPath,worker_version:VERSION}});
    components.push({name:p.name,url:p.url,sha256:p.hash,storage_path:path,evidence_id:evidenceId});
  }
  const bytes=new TextEncoder().encode(JSON.stringify({source_record_id:recordPath,worker_version:VERSION,components})),hash=await sha256(bytes),path=`layer2a/AU/scholarships/${recordPath}/manifest-${hash}.json`;
  const up=await client.storage.from("evidence").upload(path,bytes,{contentType:"application/json",upsert:true}); if(up.error) throw up.error;
  const evidenceId=await rpc(client,"svc_scholarship_register_evidence",{p_source_id:sourceId,p_source_url:sourceUrl,p_storage_path:path,p_content_hash:hash,p_mime_type:"application/json",p_metadata:{source_record_id:recordPath,worker_version:VERSION,component_evidence_ids:components.map(x=>x.evidence_id),components}});
  return {evidenceId,manifestHash:hash};
}
async function persist(client:any,sourceId:string,record:any,parts:any[],recordPath:string){
  const bundle=await registerBundle(client,sourceId,recordPath,record.source_url,parts);
  const sr={p_source_id:sourceId,p_source_record_id:record.source_record_id,p_source_record_url:record.source_url,p_source_provider_id:record.source_provider_id,p_source_provider_cricos:record.provider_cricos,p_source_provider_name:record.source_provider_name,p_content_hash:bundle.manifestHash,p_evidence_id:bundle.evidenceId,p_payload:record,p_status:"captured",p_error_text:null};
  await rpc(client,"svc_scholarship_source_record",sr);
  const applied=await rpc(client,"svc_scholarship_apply_records",{p_source_id:sourceId,p_evidence_id:bundle.evidenceId,p_records:[record],p_mode:"apply"});
  await rpc(client,"svc_scholarship_source_record",{...sr,p_status:"applied"});
  return {...bundle,applied};
}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST") return reply({error:"POST required"},405);
  const client=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false}});
  try{
    const nonce=clean(req.headers.get("x-cf-run-nonce"));
    if(!nonce||!(await rpc(client,"svc_pilot_consume_nonce",{p_function:"scholarships-au-etl",p_nonce:nonce}))) return reply({error:"valid one-time Pilot nonce required"},401);
    const body=await req.json().catch(()=>({})),mode=clean(body?.mode||"dry_run").toLowerCase(),feed=clean(body?.feed||"study_australia").toLowerCase();
    if(!["dry_run","apply"].includes(mode)) throw new Error("mode must be dry_run or apply");
    if(!["study_australia","australia_awards"].includes(feed)) throw new Error("feed must be study_australia or australia_awards");
    if(feed==="study_australia"){
      const parsed=await buildStudyAustralia(body);
      const counts=(k:string)=>parsed.reduce((n:number,x:any)=>n+x.record.cycles.reduce((m:number,c:any)=>m+(c[k]||[]).length,0),0);
      const base={ok:true,workerVersion:VERSION,mode,feed,candidateScholarships:parsed.length,sourceIdentifiers:parsed.map((x:any)=>x.record.source_record_id),mappedCricos:parsed.filter((x:any)=>x.record.provider_cricos).length,unmappedCricos:parsed.filter((x:any)=>!x.record.provider_cricos).length,cycles:parsed.reduce((n:number,x:any)=>n+x.record.cycles.length,0),windows:counts("windows"),scopes:counts("scopes"),criteria:counts("criteria"),awardTiers:counts("award_tiers"),coverage:counts("coverage"),sample:parsed.slice(0,5).map((x:any)=>({id:x.record.source_record_id,name:x.record.name,provider:x.record.source_provider_name,cricos:x.record.provider_cricos,close:x.record.application_close_date,award:x.record.award_value_text}))};
      if(mode==="dry_run") return reply(base);
      const sourceId=await prepareSource(client,feed),results=[];
      for(const x of parsed) results.push({id:x.record.source_record_id,...await persist(client,sourceId,x.record,x.evidenceParts,`study-australia/${x.record.source_record_id}`)});
      return reply({...base,sourceId,results});
    }
    const built=await buildAustraliaAwards(),c=built.record.cycles[0],base={ok:true,workerVersion:VERSION,mode,feed,candidateScholarships:1,sourceIdentifiers:["AAS"],cycles:1,windows:c.windows.length,scopes:c.scopes.length,criterionGroups:c.criterion_groups.length,criteria:c.criteria.length,awardTiers:c.award_tiers.length,coverage:c.coverage.length,sample:{id:"AAS",name:built.record.name,cycle:c.cycle_code,windows:c.windows.map((w:any)=>({code:w.round_code,opens:w.opens_at,closes:w.closes_at}))}};
    if(mode==="dry_run") return reply(base);
    const sourceId=await prepareSource(client,feed),result=await persist(client,sourceId,built.record,built.parts,"dfat-australia-awards/AAS");
    return reply({...base,sourceId,...result});
  }catch(e){return reply({ok:false,workerVersion:VERSION,error:e instanceof Error?e.message:String(e)},500);}
});
