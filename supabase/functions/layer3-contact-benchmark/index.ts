import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";

const FN="layer3-contact-benchmark",VERSION="layer3-contact-benchmark-v1.0.0";
const J=(s:number,b:any)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
const clean=(v:any)=>String(v??"").replace(/\s+/g," ").trim();
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw new Error(`${n}: ${error.message}`);return data}
function textify(s:string){return clean(s.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi," ").replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi," ").replace(/<[^>]+>/g," ").replace(/&nbsp;/gi," ").replace(/&amp;/gi,"&")).slice(0,60000)}
function parse(v:any){if(typeof v==="object"&&v)return v;return JSON.parse(String(v||"").trim().replace(/^```(?:json)?\s*/i,"").replace(/\s*```$/,""))}
function occurs(v:any,text:string){if(v==null||v==="")return true;return text.toLowerCase().includes(String(v).trim().toLowerCase())}
function validate(result:any,text:string,sourceUrl:string,expectFound:boolean){
 const errors:string[]=[];const cv=result?.candidate_value,conf=Number(result?.confidence);
 if(!result||typeof result!=="object"||Array.isArray(result))errors.push("structured_output_missing");
 if(!Number.isFinite(conf)||conf<0||conf>1)errors.push("confidence_invalid");
 if(typeof result?.rationale!=="string"||!result.rationale.trim())errors.push("rationale_required");
 if(!Array.isArray(result?.evidence_quotes))errors.push("evidence_quotes_required");
 if(!cv||typeof cv!=="object"||Array.isArray(cv))errors.push("candidate_object_required");
 const disposition=String(cv?.disposition||"");
 if(!["published_contact_found","not_publicly_published","not_found_in_qualified_evidence"].includes(disposition))errors.push("disposition_invalid");
 const contacts=Array.isArray(cv?.contacts)?cv.contacts:[];
 if(!Array.isArray(cv?.contacts))errors.push("contacts_array_required");
 if(expectFound&&disposition!=="published_contact_found")errors.push("published_contact_expected");
 if(!expectFound&&disposition==="published_contact_found")errors.push("no_contact_expected");
 if(!expectFound&&(contacts.length||cv?.general_email))errors.push("negative_control_must_not_emit_contact");
 const host=(()=>{try{return new URL(sourceUrl).hostname.toLowerCase()}catch{return""}})();
 for(const k of ["international_students_url","contact_team_url"]){const v=cv?.[k];if(v!=null){try{const u=new URL(String(v));if(u.protocol!=="https:"&&u.protocol!=="http:")errors.push(k+"_scheme");if(host&&u.hostname.toLowerCase()!==host)errors.push(k+"_host")}catch{errors.push(k+"_url")};if(!occurs(v,text)&&String(v)!==sourceUrl)errors.push(k+"_not_in_evidence")}}
 if(cv?.general_email&&!occurs(cv.general_email,text))errors.push("general_email_not_in_evidence");
 for(const x of contacts){if(!x||typeof x!=="object"){errors.push("contact_shape");continue}for(const k of ["name","title","email","phone","territory"]){if(x[k]!=null&&!occurs(x[k],text))errors.push(`contact_${k}_not_in_evidence`)}if(x.source_url!=null&&String(x.source_url)!==sourceUrl&&!occurs(x.source_url,text))errors.push("contact_source_url_not_in_evidence")}
 if(expectFound&&!contacts.length&&!cv?.general_email)errors.push("published_contact_requires_contact_or_general_email");
 return{valid:errors.length===0,errors,confidence:Number.isFinite(conf)?conf:null,candidate_value:cv??null};
}
async function callModel(profile:any,key:string,name:string,sourceUrl:string,text:string,expectFound:boolean){
 const prompt=[
  "Task class: international_contact",`Case: ${name}`,`Governed first-party source: ${sourceUrl}`,
  "Return exactly one JSON object with candidate_value, confidence, rationale, evidence_quotes.",
  "candidate_value must contain disposition, international_students_url, contact_team_url, general_email, contacts.",
  "contacts is an array of objects with name,title,email,phone,territory,source_url; use null for absent scalar values.",
  "Every emitted person, title, email, phone, territory and URL must be explicitly present in Evidence. Never infer or manufacture.",
  expectFound?"This case contains a qualifying published international contact.":"This is a no-contact control. Do not emit any contact or email.",
  "Evidence:",text
 ].join("\n\n");
 const schema={type:"object",additionalProperties:false,required:["candidate_value","confidence","rationale","evidence_quotes"],properties:{
  candidate_value:{type:"object",additionalProperties:false,required:["disposition","international_students_url","contact_team_url","general_email","contacts"],properties:{
   disposition:{type:"string",enum:["published_contact_found","not_publicly_published","not_found_in_qualified_evidence"]},
   international_students_url:{type:["string","null"]},contact_team_url:{type:["string","null"]},general_email:{type:["string","null"]},
   contacts:{type:"array",maxItems:12,items:{type:"object",additionalProperties:false,required:["name","title","email","phone","territory","source_url"],properties:{name:{type:["string","null"]},title:{type:["string","null"]},email:{type:["string","null"]},phone:{type:["string","null"]},territory:{type:["string","null"]},source_url:{type:["string","null"]}}}}
  }},confidence:{type:"number",minimum:0,maximum:1},rationale:{type:"string"},evidence_quotes:{type:"array",maxItems:4,items:{type:"string"}}
 }};
 let calls=0,input=0,output=0,cost=0,maxLatency=0,last:any=null;const returned=new Set<string>(),trace:any[]=[];
 const attempts=Math.max(1,Math.min(Number(profile.retry_ceiling||0)+1,3));
 for(let i=0;i<attempts;i++){calls++;const ctl=new AbortController(),tm=setTimeout(()=>ctl.abort(),Number(profile.timeout_ms||30000)),st=performance.now();try{
  const res=await fetch(String(profile.base_url).replace(/\/$/,"")+"/chat/completions",{method:"POST",signal:ctl.signal,headers:{"Authorization":"Bearer "+key,"Content-Type":"application/json","HTTP-Referer":"https://coursefinder.app","X-Title":"CourseFinder A16 Contact Benchmark"},body:JSON.stringify({model:profile.model_identifier,temperature:0,seed:0,max_tokens:Number(profile.max_output_tokens||1200),reasoning:{effort:"none",exclude:true},response_format:{type:"json_schema",json_schema:{name:"coursefinder_contact",strict:true,schema}},messages:[{role:"system",content:profile.prompt_system},{role:"user",content:prompt}]})});
  const payload=await res.json().catch(()=>({})),lat=Math.round(performance.now()-st);maxLatency=Math.max(maxLatency,lat);input+=Number(payload?.usage?.prompt_tokens||0);output+=Number(payload?.usage?.completion_tokens||0);cost+=Number(payload?.usage?.cost||0);if(payload?.model)returned.add(String(payload.model));
  if(!res.ok){trace.push({attempt:i+1,http_status:res.status,latency_ms:lat,outcome:"provider_error"});last={payload,parsed:null,parse_error:`aggregator ${res.status}`,latency_ms:lat};continue}
  try{const parsed=parse(payload?.choices?.[0]?.message?.content);trace.push({attempt:i+1,http_status:res.status,latency_ms:lat,outcome:"structured_output",response_model:payload?.model||null});last={payload,parsed,parse_error:null,latency_ms:lat};break}catch(e:any){trace.push({attempt:i+1,http_status:res.status,latency_ms:lat,outcome:"malformed_output"});last={payload,parsed:null,parse_error:String(e?.message||e),latency_ms:lat}}
 }catch(e:any){const lat=Math.round(performance.now()-st);maxLatency=Math.max(maxLatency,lat);trace.push({attempt:i+1,http_status:null,latency_ms:lat,outcome:"network_or_timeout"});last={payload:{},parsed:null,parse_error:String(e?.message||e),latency_ms:lat}}finally{clearTimeout(tm)}}
 return{...last,metrics:{external_calls:calls,input_tokens:input,output_tokens:output,estimated_cost_usd:cost,max_latency_ms:maxLatency,returned_models:[...returned],retry_count:Math.max(calls-1,0),attempt_trace:trace}};
}
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return J(405,{ok:false,error:"POST required",worker_version:VERSION});
 const url=Deno.env.get("SUPABASE_URL")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||(()=>{try{return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}").default||""}catch{return""}})();
 const svc=createClient(url,serviceKey,{auth:{persistSession:false}});
 try{
  const nonce=clean(req.headers.get("x-cf-run-nonce"));if(!nonce)throw new Error("one-time schedule nonce required");
  if(!await rpc(svc,"svc_pilot_consume_nonce",{p_function:FN,p_nonce:nonce}))throw new Error("invalid, expired or already-used schedule nonce");
  const body=await req.json().catch(()=>({})),ids=Array.isArray(body.evidence_ids)?body.evidence_ids.map(String).slice(0,4):[];
  if(ids.length<3)throw new Error("at least three contact evidence_ids required");
  const profile=await rpc(svc,"layer3_contact_benchmark_profile_service");
  let key=Deno.env.get(String(profile.secret_env_key||""));if(!key){const{data:vaultKey,error:vaultError}=await svc.rpc("layer3_provider_credential_resolve_service",{p_profile_id:profile.id});if(vaultError)throw new Error("contact credential lookup failed: "+vaultError.message);key=typeof vaultKey==="string"?vaultKey:""}if(!key)throw new Error("server-side contact aggregator credential unavailable");
  const evs=await rpc(svc,"layer3_contact_benchmark_evidence_service",{p_evidence_ids:ids});
  if((evs||[]).length<3)throw new Error("three retained contact Evidence artifacts required");
  const providerCases:any[]=[],controlCases:any=[],returned=new Set<string>(),used:string[]=[];let calls=0,input=0,output=0,cost=0,maxLatency=0;
  for(const ev of evs.slice(0,3)){const dl=await svc.storage.from("evidence").download(ev.storage_path);if(dl.error||!dl.data)throw new Error("evidence download failed: "+(dl.error?.message||ev.id));const text=textify(await dl.data.text());const result=await callModel(profile,key,`real-${ev.id}`,ev.source_url,text,true);const val=validate(result.parsed,text,ev.source_url,true);for(const m of result.metrics.returned_models)returned.add(m);calls+=result.metrics.external_calls;input+=result.metrics.input_tokens;output+=result.metrics.output_tokens;cost+=result.metrics.estimated_cost_usd;maxLatency=Math.max(maxLatency,result.metrics.max_latency_ms);providerCases.push({evidence_id:ev.id,source_url:ev.source_url,valid:val.valid&&!result.parse_error,errors:[...val.errors,...(result.parse_error?[result.parse_error]:[])],confidence:val.confidence,candidate_value:val.candidate_value,model:result.payload?.model||null,latency_ms:result.latency_ms,retry_count:result.metrics.retry_count,attempt_trace:result.metrics.attempt_trace});used.push(ev.id)}
  const synth=[
   {name:"positive-explicit",source:"https://example.edu/international/contact",text:"International admissions team. Email international@example.edu. Regional Manager South Asia: Priya Singh. Territory South Asia. Phone +61 2 5555 0101. Source https://example.edu/international/contact",found:true},
   {name:"negative-no-contact",source:"https://example.edu/international",text:"Welcome to international study. Browse programmes, scholarships and accommodation. No staff contact details or admissions email are published on this page.",found:false},
   {name:"anti-hallucination",source:"https://example.edu/study",text:"International study information. This page contains no recruitment manager names, no phone numbers and no admissions email addresses. Contact details are not published here.",found:false}
  ];
  for(const x of synth){const result=await callModel(profile,key,x.name,x.source,x.text,x.found);const val=validate(result.parsed,x.text,x.source,x.found);for(const m of result.metrics.returned_models)returned.add(m);calls+=result.metrics.external_calls;input+=result.metrics.input_tokens;output+=result.metrics.output_tokens;cost+=result.metrics.estimated_cost_usd;maxLatency=Math.max(maxLatency,result.metrics.max_latency_ms);controlCases.push({case:x.name,valid:val.valid&&!result.parse_error,errors:[...val.errors,...(result.parse_error?[result.parse_error]:[])],confidence:val.confidence,candidate_value:val.candidate_value,model:result.payload?.model||null,latency_ms:result.latency_ms,retry_count:result.metrics.retry_count,attempt_trace:result.metrics.attempt_trace})}
  const providerPass=providerCases.length===3&&providerCases.every(x=>x.valid),controlsPass=controlCases.every(x=>x.valid),modelPass=[...returned].length>0&&[...returned].every(x=>x===String(profile.model_identifier)),costPass=cost<=Number(profile.cost_ceiling_usd||0),pass=providerPass&&controlsPass&&modelPass&&costPass;
  const summary=`contact benchmark: provider ${providerCases.filter(x=>x.valid).length}/3; controls ${controlCases.filter(x=>x.valid).length}/3; model_exact=${modelPass}; cost_usd=${cost.toFixed(6)}`;
  const recorded=await rpc(svc,"layer3_contact_benchmark_record_service",{p_pass:pass,p_provider_cases:providerCases,p_control_cases:controlCases,p_returned_models:[...returned],p_external_call_count:calls,p_input_tokens:input,p_output_tokens:output,p_estimated_cost_usd:cost,p_max_latency_ms:maxLatency,p_evidence_ids:used,p_summary:summary});
  return J(pass?200:422,{ok:pass,worker_version:VERSION,summary,provider_cases:providerCases,control_cases:controlCases,returned_models:[...returned],external_call_count:calls,input_tokens:input,output_tokens:output,estimated_cost_usd:cost,max_latency_ms:maxLatency,recorded});
 }catch(e:any){return J(500,{ok:false,error:String(e?.message||e),worker_version:VERSION})}
});