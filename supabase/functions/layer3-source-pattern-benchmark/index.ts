import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";

const FN="layer3-source-pattern-benchmark",VERSION="layer3-source-pattern-benchmark-v1.0.6";
const J=(s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
const clean=(v:any)=>String(v??"").replace(/\s+/g," ").trim();
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw new Error(`${n}: ${error.message}`);return data}
function strip(s:string){return clean(s.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi," ").replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi," ").replace(/<[^>]+>/g," ").replace(/&nbsp;/gi," ").replace(/&amp;/gi,"&"))}
function extractLinks(html:string,base:string){
 const out:any[]=[],seen=new Set<string>(),re=/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;let m:RegExpExecArray|null;const b=new URL(base);
 while((m=re.exec(html))){try{const u=new URL(m[1],base);u.hash="";if(u.protocol!=="https:"||u.hostname.toLowerCase()!==b.hostname.toLowerCase())continue;const k=u.toString();if(seen.has(k))continue;seen.add(k);out.push({url:k,text:strip(m[2]).slice(0,180)})}catch{}}
 return out;
}
function parseContent(v:any){if(typeof v==="object"&&v)return v;const s=String(v||"").trim().replace(/^\`\`\`(?:json)?\s*/i,"").replace(/\s*\`\`\`$/,"");return JSON.parse(s)}
function validate(result:any,links:any[],host:string,expected:string|null,negative:boolean){
 const errors:string[]=[];if(!result||typeof result!=="object"||Array.isArray(result))errors.push("structured_output_missing");const conf=Number(result?.confidence);
 if(!Number.isFinite(conf)||conf<0||conf>1)errors.push("confidence_invalid");
 if(typeof result?.rationale!=="string"||!result.rationale.trim())errors.push("rationale_required");
 if(!Array.isArray(result?.evidence_quotes))errors.push("evidence_quotes_required");
 const cv=result?.candidate_value;
 if(negative){
  if(cv!==null)errors.push("negative_control_must_be_null");
 } else {
  const u=typeof cv==="string"?cv:"";
  if(!/^https:\/\//i.test(u))errors.push("https_catalogue_url_required");
  else {
   try{const x=new URL(u);if(x.hostname.toLowerCase()!==host.toLowerCase())errors.push("same_host_required")}catch{errors.push("url_invalid")}
   if(!links.some(x=>x.url===u))errors.push("candidate_not_in_evidence_links");
   if(expected&&u!==expected)errors.push("expected_control_url_mismatch");
  }
 }
 return {valid:errors.length===0,errors,confidence:Number.isFinite(conf)?conf:null,candidate_value:cv??null};
}
async function callModel(profile:any,key:string,caseName:string,sourceUrl:string,links:any[],negative=false){
 const prompt=[
  `Task class: source_pattern`,
  `Case: ${caseName}`,
  `Governed first-party host: ${new URL(sourceUrl).hostname}`,
  "Choose at most one Course/programme catalogue or discovery entrypoint from the supplied Evidence links.",
  "The candidate URL MUST appear exactly in the supplied links and MUST stay on the governed host.",
  "Do not infer Course identity, regulatory codes, fees, admissions, Search actions or Publication actions.",
  negative?"This is a negative control. No Course/programme catalogue link is present, so candidate_value must be null.":"",
  'Return exactly: {"candidate_value":null OR "https://...", "confidence":0..1, "rationale":"...", "evidence_quotes":["..."]}.',
  "Evidence links:",
  ...links.slice(0,60).map((x:any)=>`- ${x.text||"(no text)"} :: ${x.url}`)
 ].filter(Boolean).join("\n");
 let last:any=null;
 const attempts=Math.max(1,Math.min(Number(profile.retry_ceiling||0)+1,2));
 for(let attempt=0;attempt<attempts;attempt++){
  const ctl=new AbortController(),tm=setTimeout(()=>ctl.abort(),Number(profile.timeout_ms||30000)),st=performance.now();
  try{
   const res=await fetch(String(profile.base_url).replace(/\/$/,"")+"/chat/completions",{
    method:"POST",signal:ctl.signal,
    headers:{"Authorization":"Bearer "+key,"Content-Type":"application/json","HTTP-Referer":"https://coursefinder.app","X-Title":"CourseFinder Source Pattern Benchmark"},
    body:JSON.stringify({model:profile.model_identifier,temperature:0,seed:0,max_tokens:Number(profile.max_output_tokens||1200),reasoning:{effort:"none",exclude:true},response_format:{type:"json_schema",json_schema:{name:"coursefinder_source_pattern",strict:true,schema:{type:"object",additionalProperties:false,required:["candidate_value","confidence","rationale","evidence_quotes"],properties:{candidate_value:{type:["string","null"]},confidence:{type:"number",minimum:0,maximum:1},rationale:{type:"string"},evidence_quotes:{type:"array",items:{type:"string"}}}}}},messages:[{role:"system",content:profile.prompt_system},{role:"user",content:prompt}]})
   });
   const payload=await res.json().catch(()=>({}));
   if(!res.ok){last={payload,parsed:null,parse_error:`aggregator ${res.status}`,latency_ms:Math.round(performance.now()-st)};continue}
   let parsed:any=null,parse_error:string|null=null;try{parsed=parseContent(payload?.choices?.[0]?.message?.content)}catch(e:any){parse_error=String(e.message||e)}
   last={payload,parsed,parse_error,latency_ms:Math.round(performance.now()-st)};
   if(parsed&&!parse_error)return last;
  }finally{clearTimeout(tm)}
 }
 return last;
}
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return J(405,{ok:false,error:"POST required",worker_version:VERSION});
 const url=Deno.env.get("SUPABASE_URL")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||(()=>{try{return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}").default||""}catch{return""}})();
 const svc=createClient(url,serviceKey,{auth:{persistSession:false}});
 try{
  const nonce=clean(req.headers.get("x-cf-run-nonce"));if(!nonce)throw new Error("one-time schedule nonce required");
  if(!await rpc(svc,"svc_pilot_consume_nonce",{p_function:FN,p_nonce:nonce}))throw new Error("invalid, expired or already-used schedule nonce");
  const body=await req.json().catch(()=>({})),evidenceIds=Array.isArray(body.evidence_ids)?body.evidence_ids.map(String).slice(0,4):[];
  if(evidenceIds.length<3)throw new Error("at least three evidence_ids required");
  const profile=await rpc(svc,"layer3_source_pattern_benchmark_profile_service");
  if(!profile?.enabled)throw new Error("source-pattern profile disabled");
  let key=Deno.env.get(String(profile.secret_env_key||""));if(!key){const {data:vaultKey,error:vaultError}=await svc.rpc("layer3_provider_credential_resolve_service",{p_profile_id:profile.id});if(vaultError)throw new Error("source-pattern credential lookup failed: "+vaultError.message);key=typeof vaultKey==="string"?vaultKey:""}if(!key)throw new Error("server-side source-pattern aggregator credential unavailable");
  const evs=await rpc(svc,"layer3_source_pattern_benchmark_evidence_service",{p_evidence_ids:evidenceIds});
  const providerCases:any[]=[],controlCases:any[]=[],returned=new Set<string>(),usedEvidence:string[]=[];let calls=0,input=0,output=0,cost=0,maxLatency=0;
  for(const ev of evs||[]){
   if(!ev.storage_path||!ev.source_url)continue;
   const dl=await svc.storage.from("evidence").download(ev.storage_path);if(dl.error||!dl.data)throw new Error("evidence download failed: "+(dl.error?.message||ev.id));
   const html=await dl.data.text(),allLinks=extractLinks(html,ev.source_url),relevant=allLinks.filter((x:any)=>/(course|program|programme|degree|qualification|study|subject)/i.test((x.text||"")+" "+x.url)),links=(relevant.length?relevant:allLinks).slice(0,60);
   const result=await callModel({...profile,max_output_tokens:Math.max(Number(profile.max_output_tokens||800),1200)},key,`provider-evidence-${ev.id}`,ev.source_url,links,false);
   calls++;input+=Number(result.payload?.usage?.prompt_tokens||0);output+=Number(result.payload?.usage?.completion_tokens||0);cost+=Number(result.payload?.usage?.cost||0);maxLatency=Math.max(maxLatency,result.latency_ms);if(result.payload?.model)returned.add(String(result.payload.model));
   const val=validate(result.parsed,links,new URL(ev.source_url).hostname,null,false);
   providerCases.push({evidence_id:ev.id,source_url:ev.source_url,link_count:links.length,valid:val.valid,errors:[...val.errors,...(result.parse_error?[result.parse_error]:[])],candidate_value:val.candidate_value,confidence:val.confidence,model:result.payload?.model||null,latency_ms:result.latency_ms});
   usedEvidence.push(String(ev.id));
  }
  const synth=[
   {name:"positive-courses",source:"https://example.edu/",links:[{text:"Library",url:"https://example.edu/library"},{text:"Explore Courses",url:"https://example.edu/courses"},{text:"Apply",url:"https://example.edu/apply"}],expected:"https://example.edu/courses",negative:false},
   {name:"positive-qualifications",source:"https://example.edu/",links:[{text:"Study support",url:"https://example.edu/support"},{text:"Find a qualification",url:"https://example.edu/study/qualifications"},{text:"Scholarships",url:"https://example.edu/scholarships"}],expected:"https://example.edu/study/qualifications",negative:false},
   {name:"negative-no-catalogue",source:"https://example.edu/",links:[{text:"Library",url:"https://example.edu/library"},{text:"Apply",url:"https://example.edu/apply"},{text:"Contact",url:"https://example.edu/contact"}],expected:null,negative:true}
  ];
  for(const c of synth){
   const result=await callModel(profile,key,c.name,c.source,c.links,c.negative);
   calls++;input+=Number(result.payload?.usage?.prompt_tokens||0);output+=Number(result.payload?.usage?.completion_tokens||0);cost+=Number(result.payload?.usage?.cost||0);maxLatency=Math.max(maxLatency,result.latency_ms);if(result.payload?.model)returned.add(String(result.payload.model));
   const val=validate(result.parsed,c.links,new URL(c.source).hostname,c.expected,c.negative);
   controlCases.push({case:c.name,valid:val.valid&&!result.parse_error,errors:[...val.errors,...(result.parse_error?[result.parse_error]:[])],candidate_value:val.candidate_value,confidence:val.confidence,model:result.payload?.model||null,latency_ms:result.latency_ms});
  }
  const providerPass=providerCases.length>=3&&providerCases.every(x=>x.valid&&x.errors.length===0);
  const controlsPass=controlCases.every(x=>x.valid);
  const modelPass=[...returned].every(x=>x===String(profile.model_identifier));
  const costPass=cost<=Number(profile.cost_ceiling_usd||0);
  const pass=providerPass&&controlsPass&&modelPass&&costPass;
  const summary=`source-pattern benchmark: provider ${providerCases.filter(x=>x.valid).length}/${providerCases.length}; controls ${controlCases.filter(x=>x.valid).length}/${controlCases.length}; model_exact=${modelPass}; cost_usd=${cost.toFixed(6)}`;
  const recorded=await rpc(svc,"layer3_source_pattern_benchmark_record_service",{p_pass:pass,p_provider_cases:providerCases,p_control_cases:controlCases,p_returned_models:[...returned],p_external_call_count:calls,p_input_tokens:input,p_output_tokens:output,p_estimated_cost_usd:cost,p_max_latency_ms:maxLatency,p_evidence_ids:usedEvidence,p_summary:summary});
  return J(pass?200:422,{ok:pass,worker_version:VERSION,summary,provider_cases:providerCases,control_cases:controlCases,returned_models:[...returned],external_call_count:calls,input_tokens:input,output_tokens:output,estimated_cost_usd:cost,max_latency_ms:maxLatency,recorded});
 }catch(e:any){return J(500,{ok:false,error:String(e.message||e),worker_version:VERSION})}
});