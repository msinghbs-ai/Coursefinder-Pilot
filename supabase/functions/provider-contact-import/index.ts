import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGIN="https://coursefinder-pilot.techm.workers.dev";
const LOCAL=new Set(["http://localhost:5173","http://127.0.0.1:5173"]);
const MAX_BYTES=10*1024*1024;
const REQUIRED=[
  "gug_2026_university_name","current_institution_name","institution_status","staff_name","job_title",
  "functional_area","region_scope","countries_or_markets","email","phone","staff_location",
  "contact_record_type","verification_status","verified_on","official_source_url","source_page_title","notes"
];
const cors=(req:Request)=>{const o=req.headers.get("origin")||"";const allow=o===ORIGIN||LOCAL.has(o)?o:ORIGIN;return {
  "access-control-allow-origin":allow,"access-control-allow-headers":"authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods":"POST, OPTIONS","cache-control":"no-store","vary":"origin"
}};
const json=(req:Request,status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors(req),"content-type":"application/json; charset=utf-8"}});
const clean=(v:FormDataEntryValue|null)=>String(v??"").trim();
const safe=(v:string)=>v.replace(/[^a-zA-Z0-9._-]+/g,"-").replace(/^-+|-+$/g,"").slice(0,120)||"provider-contacts.csv";
const sha256=async(bytes:ArrayBuffer)=>[...new Uint8Array(await crypto.subtle.digest("SHA-256",bytes))].map(b=>b.toString(16).padStart(2,"0")).join("");

function parseCsv(text:string){
  const rows:string[][]=[];let row:string[]=[],field="",quoted=false;
  for(let i=0;i<text.length;i++){
    const ch=text[i];
    if(quoted){
      if(ch==='"'&&text[i+1]==='"'){field+='"';i++;continue}
      if(ch==='"'){quoted=false;continue}
      field+=ch;continue
    }
    if(ch==='"'){quoted=true;continue}
    if(ch===","){row.push(field);field="";continue}
    if(ch==="\n"||ch==="\r"){
      if(ch==="\r"&&text[i+1]==="\n")i++;
      row.push(field);field="";
      if(row.some(x=>x!==""))rows.push(row);
      row=[];continue
    }
    field+=ch
  }
  if(quoted)throw new Error("unterminated_csv_quote");
  if(field!==""||row.length){row.push(field);if(row.some(x=>x!==""))rows.push(row)}
  return rows
}
function isoDate(raw:string,format:string){
  const v=raw.trim();if(!v)return "";
  if(/^\d{4}-\d{2}-\d{2}$/.test(v))return v;
  const m=v.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);if(!m)throw new Error("unsupported_verified_on_date:"+v);
  const a=Number(m[1]),b=Number(m[2]),y=Number(m[3]);
  const month=format==="dmy"?b:a,day=format==="dmy"?a:b;
  if(month<1||month>12||day<1||day>31)throw new Error("invalid_verified_on_date:"+v);
  return `${y}-${String(month).padStart(2,"0")}-${String(day).padStart(2,"0")}`;
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors(req)});
  if(req.method!=="POST")return json(req,405,{error:"method_not_allowed"});
  const auth=req.headers.get("authorization")||"";
  if(!auth.toLowerCase().startsWith("bearer "))return json(req,401,{error:"authentication_required"});
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)return json(req,500,{error:"service_configuration_error"});

  const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const {data:ctx,error:ctxErr}=await user.rpc("admin_read",{p_operation:"context",p_args:{}});
  if(ctxErr||!ctx?.authenticated)return json(req,401,{error:"authentication_required"});
  if(Number(ctx.role_rank||0)<5)return json(req,403,{error:"pim_admin_role_required"});
  const actor=String(ctx.user_id||"");
  if(!/^[0-9a-f-]{36}$/i.test(actor))return json(req,403,{error:"operator_context_invalid"});

  let form:FormData;try{form=await req.formData()}catch{return json(req,400,{error:"multipart_form_required"})}
  const country=(clean(form.get("country_code"))||"AU").toUpperCase();
  const dateFormat=(clean(form.get("date_format"))||"mdy").toLowerCase();
  if(!/^[A-Z]{2}$/.test(country))return json(req,400,{error:"valid_country_code_required"});
  if(!["mdy","dmy"].includes(dateFormat))return json(req,400,{error:"date_format_must_be_mdy_or_dmy"});
  const file=form.get("file");
  if(!(file instanceof File))return json(req,400,{error:"provider_contact_csv_required"});
  if(file.size<=0||file.size>MAX_BYTES)return json(req,400,{error:"file_size_out_of_range",max_bytes:MAX_BYTES});
  if(!file.name.toLowerCase().endsWith(".csv"))return json(req,400,{error:"csv_file_required"});
  const mime=(file.type||"text/csv").toLowerCase();
  if(!["text/csv","text/plain","application/vnd.ms-excel","application/octet-stream"].includes(mime))return json(req,400,{error:"unsupported_csv_mime",mime_type:mime});

  const bytes=await file.arrayBuffer();
  let parsed:string[][];
  try{parsed=parseCsv(new TextDecoder().decode(bytes).replace(/^\uFEFF/,""))}catch(e){return json(req,400,{error:"csv_parse_failed",detail:e instanceof Error?e.message:String(e)})}
  if(parsed.length<2)return json(req,400,{error:"csv_has_no_data_rows"});
  const headers=parsed[0].map(x=>x.trim());
  const missing=REQUIRED.filter(x=>!headers.includes(x));
  if(missing.length)return json(req,400,{error:"provider_contact_csv_contract_mismatch",missing_columns:missing,required_columns:REQUIRED});
  const index=new Map(headers.map((h,i)=>[h,i]));
  const rows:any[]=[];
  try{
    for(let i=1;i<parsed.length;i++){
      const cells=parsed[i];const out:any={};
      for(const h of REQUIRED)out[h]=String(cells[index.get(h)!]??"").trim();
      out.verified_on=isoDate(out.verified_on,dateFormat);
      rows.push(out);
    }
  }catch(e){return json(req,400,{error:"csv_normalisation_failed",detail:e instanceof Error?e.message:String(e)})}

  const hash=await sha256(bytes),nonce=crypto.randomUUID();
  const path=`provider-contacts/${country}/${hash.slice(0,16)}-${nonce}-${safe(file.name)}`;
  const svc=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const upload=await svc.storage.from("evidence").upload(path,new Uint8Array(bytes),{contentType:mime,upsert:false,cacheControl:"0"});
  if(upload.error)return json(req,500,{error:"evidence_upload_failed",detail:upload.error.message});

  const {data:reg,error:regErr}=await svc.rpc("svc_provider_contact_import_register",{
    p_country_code:country,p_original_filename:file.name,p_mime_type:mime,p_byte_size:file.size,
    p_content_hash:hash,p_storage_path:path,p_uploaded_by:actor
  });
  if(regErr){await svc.storage.from("evidence").remove([path]);return json(req,500,{error:"import_registration_failed",detail:regErr.message})}
  if(reg?.duplicate){await svc.storage.from("evidence").remove([path]);return json(req,200,{ok:true,duplicate:true,batch_id:reg.batch_id,content_hash:hash})}

  const batchId=String(reg?.batch_id||"");
  const {data:dry,error:dryErr}=await svc.rpc("svc_provider_contact_import_validate",{p_batch_id:batchId,p_rows:rows,p_actor:actor});
  if(dryErr){
    await svc.schema("pipeline").from("provider_contact_import_batches").update({
      status:"failed",metadata:{change_control:"CF-CHG-20260902-080",validation_error:dryErr.message}
    }).eq("id",batchId);
    return json(req,422,{ok:false,error:"contact_import_validation_failed",detail:dryErr.message,batch_id:batchId})
  }
  const {data:parked,error:parkErr}=await svc.rpc("svc_provider_contact_import_park_layer4",{p_batch_id:batchId,p_actor:actor});
  if(parkErr){
    await svc.schema("pipeline").from("provider_contact_import_batches").update({
      status:"failed",metadata:{change_control:"CF-CHG-20260902-080",layer4_parking_error:parkErr.message}
    }).eq("id",batchId);
    return json(req,422,{ok:false,error:"contact_import_layer4_parking_failed",detail:parkErr.message,batch_id:batchId})
  }
  return json(req,201,{ok:true,duplicate:false,batch_id:batchId,evidence_id:reg.evidence_id,content_hash:hash,
    original_filename:file.name,row_count:rows.length,date_format:dateFormat,
    dry_run:{...(dry||{}),...(parked||{}),layer4_review_pending:Number(parked?.layer4_review_pending||0)}});
});