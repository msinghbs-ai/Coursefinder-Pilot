// CF-247 Phase 2 (8 Oct 2026): reference readers for the Canadian catalogue replays. Each function is the worker's own parsing code,
// copied without change from the worker named in its comment (helpers and the parsing statements; the provider code and name, which
// come from the database, are left empty). A contract test checks every copied piece is still in the worker. Generated; do not edit.

// layer1-ca-algonquin-catalogue
export function ref_algonquin(text: string): any[] {
const clean=(v:any)=>String(v??"").trim();
function decode(s:string){return clean(s).replace(/&amp;/g,"&").replace(/&#8211;/g,"–").replace(/&#x2013;/gi,"–").replace(/&#39;|&#x27;/gi,"'").replace(/&quot;/g,'"').replace(/&nbsp;/g," ");}
const DLI="";const provider:any={};
const m=text.match(/window\.programTableValues\s*=\s*(\{[\s\S]*?\});\s*<\/script>/);if(!m)throw new Error("Algonquin programTableValues payload not found");const payload=JSON.parse(m[1]);const rows=Array.isArray(payload?.data)?payload.data:[];const dedup=new Map<string,any>();for(const r of rows){const code=clean(r.programcode),title=decode(r.programname);if(!code||!title)continue;dedup.set(code,{provider_code:DLI,provider_name:provider.canonical_name||"Algonquin College",local_program_id:code,course_title:title,issuing_authority:"Algonquin College",delivery:clean(r.delivery)||null,area_of_interest:clean(r.aoi)||null});}
return [...dedup.values()];
}

// layer1-ca-boreal-programs
export function ref_boreal(html: string): any[] {
const t=(x:any)=>String(x??"").trim();
function dec(s:string){return t(s).replace(/&rsquo;|&#8217;|&#x27;|&#39;/gi,"’").replace(/&#8211;|&#x2013;/gi,"–").replace(/&amp;|&#038;/gi,"&").replace(/&quot;/gi,'"');}
const DLI="";const rows:any[]=[],seen=new Set<string>();
for(const part of html.split('<div class="c-card js-filter-page-element').slice(1)){const sm=part.match(/href="https:\/\/collegeboreal\.ca\/programme\/([^/]+)\//),tm=part.match(/data-title="([^"]+)"/),sess=part.match(/data-filter-programme_session="([^"]*)"/);if(!sm||!tm)continue;const id=t(sm[1]),title=dec(tm[1]),session=t(sess?.[1]||"");if(!id||!title||seen.has(id))continue;seen.add(id);rows.push({provider_code:DLI,provider_name:"Collège Boréal",local_program_id:id,course_title:title,issuing_authority:"Collège Boréal",lifecycle_status:session?"active":"unknown"});}
return rows;
}

// layer1-ca-cambrian-programs
export function ref_cambrian(html: string): any[] {
const t=(x:any)=>String(x??"").trim();
const MONTHS:any={january:0,february:1,march:2,april:3,may:4,june:5,july:6,august:7,september:8,october:9,november:10,december:11};
function dec(s:string){return t(s).replace(/&amp;/g,"&").replace(/&nbsp;/g," ").replace(/&#x2013;|&#8211;/gi,"–").replace(/&#x27;|&#39;/gi,"'").replace(/&quot;/g,'"');}
function hasFutureStart(part:string){const now=new Date(),floor=Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),1);const re=/"course_date":"([A-Za-z]+)\s+(\d{4})"/g;let m;while((m=re.exec(part))!==null){const mon=MONTHS[m[1].toLowerCase()],yr=Number(m[2]);if(mon!==undefined&&Date.UTC(yr,mon,1)>=floor)return true;}return false;}
const DLI="";
const norm=html.replace(/\\+/g,"");const parts=norm.split('{"id":').slice(1),m=new Map<string,any>(),secondary=new Map<string,string>(),duplicateSecondaryCodes:string[]=[];let parserConflicts=0,missingCodes=0;for(const part of parts){const h=part.match(/^(\d+),"slug":"([^"]+)","title":\{"rendered":"([^"]+)"\}/);if(!h||!part.includes('"acf":'))continue;const id=t(h[1]),slug=t(h[2]),title=dec(h[3]),cm=part.match(/"program_code":"([^"]*)"/),code=t(cm?.[1]);if(!id||!title)continue;const prior=m.get(id);if(prior&&prior.course_title!==title){parserConflicts++;continue;}if(code){const prev=secondary.get(code);if(prev&&prev!==id&&!duplicateSecondaryCodes.includes(code))duplicateSecondaryCodes.push(code);else secondary.set(code,id);}else missingCodes++;const active=hasFutureStart(part);m.set(id,{provider_code:DLI,provider_name:"Cambrian College of Applied Arts and Technology",local_program_id:id,course_title:title,issuing_authority:"Cambrian College",lifecycle_status:active?"active":"unknown",source_slug:slug,program_code:code||null,...(code?{regional_reg_scheme:"cambrian_program_code",regional_reg_code:code}:{})});}
return [...m.values()];
}

// layer1-ca-conestoga-catalogue
export function ref_conestoga(text: string): any[] {
const clean=(v:any)=>String(v??"").trim();
function decode(s:string){return clean(s).replace(/&amp;/g,"&").replace(/&#x2013;/gi,"–").replace(/&#x27;|&#39;/gi,"'").replace(/&quot;/g,'"').replace(/&nbsp;/g," ");}
const DLI="";const provider:any={};
const re=/ProgramCode=([^"&]+)[^"]*">([^<]+)<\/a><\/td><td[^>]*data-title="Program code:">([^<]+)<\/td>/g;const dedup=new Map<string,any>();let rawRows=0,duplicateRows=0,conflicts=0;for(const m of text.matchAll(re)){rawRows++;const code=clean(m[1]),cellCode=clean(m[3]),title=decode(m[2]);if(!code||code!==cellCode||!title){conflicts++;continue;}const prior=dedup.get(code);if(prior){duplicateRows++;if(prior.course_title!==title)conflicts++;continue;}dedup.set(code,{provider_code:DLI,provider_name:provider.canonical_name||"Conestoga College",local_program_id:code,course_title:title,issuing_authority:"Conestoga College"});}
return [...dedup.values()];
}

// layer1-ca-confederation-programs
export function ref_confederation(text: string): any[] {
const t=(x:any)=>String(x??"").trim();
const DLI="";
const doc=JSON.parse(text),allowed=new Set(["degree","diploma","certificate"]),rows:any[]=[],seen=new Set<string>();for(const p of doc.programs??[]){const id=t(p.id),title=t(p.title),cat=t(p.credential?.category),intakes=Array.isArray(p.intakes)?p.intakes:[];if(!id||!title||!allowed.has(cat)||!intakes.some((i:any)=>i.studyMode==="Full-Time"))continue;if(seen.has(id))throw new Error(`duplicate Confederation programme id ${id}`);seen.add(id);rows.push({provider_code:DLI,provider_name:"Confederation College",local_program_id:id,course_title:title,issuing_authority:"Confederation College",lifecycle_status:"active"});}
return rows;
}

// layer1-ca-durham-programs
export function ref_durham(text: string): any[] {
const clean=(v:any)=>String(v??"").trim();
const DLI="";
const data=JSON.parse(text);if(!Array.isArray(data))throw new Error("Durham payload not array");const map=new Map<string,any>(),ocas=new Map<string,Set<string>>();let missing=0;for(const r of data){const id=clean(r.id),title=clean(r.title);if(!id||!title){missing++;continue;}map.set(id,{provider_code:DLI,provider_name:"Durham College",local_program_id:id,course_title:title,issuing_authority:"Durham College"});const o=clean(r.OCAS);if(o&&o.toUpperCase()!=="N/A"){if(!ocas.has(o))ocas.set(o,new Set());ocas.get(o)!.add(title);}}
return [...map.values()];
}

// layer1-ca-fanshawe-pgwp
export function ref_fanshawe_pgwp(text: string): any[] {
const clean=(v:any)=>String(v??"").trim();
function dec(s:string){return clean(s).replace(/&amp;/g,"&").replace(/&#x27;|&#39;/gi,"'").replace(/&#x2013;/gi,"–").replace(/&quot;/g,'"').replace(/&nbsp;/g," ")}
const DLI="";const p:any={};
const re=/<tr><td>([^<]+)<\/td><td><a href="([^"]+)">([^<]+)<\/a><\/td><td>([^<]*)<\/td><td>([^<]*)<\/td><td>([^<]*)<\/td><\/tr>/g,dedup=new Map<string,any>();let rawRows=0,conflicts=0;for(const m of text.matchAll(re)){rawRows++;const code=clean(m[1]),title=dec(m[3]);if(!code||!title){conflicts++;continue}const rec={provider_code:DLI,provider_name:p.canonical_name||"Fanshawe College",local_program_id:code,course_title:title,issuing_authority:"Fanshawe College",credential:dec(m[4]),start_dates:dec(m[5]),cip:clean(m[6])};const prior=dedup.get(code);if(prior&&prior.course_title!==title){conflicts++;continue}dedup.set(code,rec)}
return [...dedup.values()];
}

// layer1-ca-fleming-programs
export function ref_fleming(html: string): any[] {
const txt=(x:any)=>String(x??"").trim();
function clean(s:string){return txt(s).replace(/&amp;/g,"&").replace(/&#0?39;|&#x27;/gi,"'").replace(/&quot;/g,'"').replace(/&#8211;|&#x2013;/gi,"–");}
function current(starts:string){const order:any={january:0,february:1,march:2,april:3,may:4,june:5,july:6,august:7,september:8,october:9,november:10,december:11},d=new Date(),floor=Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),1),re=/([A-Za-z]+) (\d{4})/g;let m;while((m=re.exec(starts))){const mon=order[m[1].toLowerCase()];if(mon!==undefined&&Date.UTC(Number(m[2]),mon,1)>=floor)return true;}return false;}
const DLI="";const rows:any[]=[],seen=new Set<string>();
for(const part of html.split('data-filterable="true"').slice(1)){const gm=part.match(/data-guid="([^"]+)"/),nm=part.match(/data-name="([^"]+)"/);if(!gm||!nm)continue;const id=txt(gm[1]),title=clean(nm[1]);if(!id||!title||seen.has(id))continue;seen.add(id);const sm=part.match(/icon-calendar-blank">([^<]+)<\/p>/),starts=clean(sm?.[1]||"");rows.push({provider_code:DLI,provider_name:"Fleming College",local_program_id:id,course_title:title,issuing_authority:"Fleming College",lifecycle_status:current(starts)?"active":"unknown"});}
return rows;
}

// layer1-ca-georgian-catalogue
export function ref_georgian(html: string): any[] {
const t=(x:any)=>String(x??"").trim();
function dec(s:string){return t(s).replace(/&amp;/g,"&").replace(/&nbsp;/g," ").replace(/&#x2013;|&#8211;/gi,"–").replace(/&#x27;|&#39;/gi,"'").replace(/&quot;/g,'"');}
const DLI="";
const re=/<li><a href="\/programs\/([^/]+)\/">([^<]+)<\/a><\/li>/g,m=new Map<string,any>();let z,conflicts=0;while((z=re.exec(html))!==null){const code=t(z[1]).toLowerCase(),title=dec(z[2]);if(!code||!title)continue;const prior=m.get(code);if(prior&&prior.course_title!==title){conflicts++;continue;}m.set(code,{provider_code:DLI,provider_name:"Georgian College",local_program_id:code,course_title:title,issuing_authority:"Georgian College",lifecycle_status:"active"});}
return [...m.values()];
}

// layer1-ca-lambton-programs
export function ref_lambton(html: string): any[] {
const t=(x:any)=>String(x??"").trim();
function dec(s:string){return t(s).replace(/&amp;/g,"&").replace(/&#x27;|&#39;/gi,"'").replace(/&quot;/g,'"').replace(/&#8211;|&#x2013;/gi,"–");}
const DLI="";
const re=/data-startdate="([^"]*)"data-wie="[^"]*"data-code="([^"]+)"data-title="([^"]+)"data-delivery="([^"]+)"/gi,m=new Map<string,any>();let z;while((z=re.exec(html))!==null){const starts=t(z[1]).toLowerCase(),code=t(z[2]).toUpperCase(),title=dec(z[3]);if(!code||!title)continue;const prior=m.get(code);if(prior&&prior.course_title!==title)throw new Error(`Lambton conflicting programme code ${code}`);m.set(code,{provider_code:DLI,provider_name:"Lambton College",local_program_id:code,course_title:title,issuing_authority:"Lambton College",lifecycle_status:starts?"active":"unknown",delivery:t(z[4]).toLowerCase(),start_terms:starts});}
return [...m.values()];
}

// layer1-ca-loyalist-programs
export function ref_loyalist(html: string): any[] {
const t=(x:any)=>String(x??"").trim();
function clean(s:string){return t(s).replace(/<[^>]+>/g,"").replace(/\s+/g," ").replace(/&amp;/g,"&").replace(/&#8211;|&#x2013;/gi,"–").replace(/&#x27;|&#39;/gi,"'").replace(/&quot;/g,'"');}
function positiveStart(part:string){return /January \(Winter\)|May \(Spring\)|September \(Fall(?: 2026| 2027)?\)|Ongoing|>Other</i.test(part);}
const DLI="";const m=new Map<string,any>();
for(const part of html.split('<li class="accordion-item loc-programs-list__item">').slice(1)){const im=part.match(/data-bs-target="#accordion-([0-9]+)"/),tm=part.match(/<h3[^>]*>([\s\S]*?)<\/h3>/),sm=part.match(/href="https:\/\/loyalistcollege\.com\/program\/([^"]+)\/"/);if(!im||!tm||!sm)continue;const id=t(im[1]),title=clean(tm[1]),slug=t(sm[1]);if(!id||!title||!slug)continue;const prior=m.get(id);if(prior&&prior.course_title!==title)throw new Error(`Loyalist conflicting programme id ${id}`);m.set(id,{provider_code:DLI,provider_name:"Loyalist College",local_program_id:id,course_title:title,issuing_authority:"Loyalist College",lifecycle_status:positiveStart(part)?"active":"unknown",source_slug:slug});}
return [...m.values()];
}

// layer1-ca-mohawk-catalogue
export function ref_mohawk(text: string): any[] {
const clean=(v:any)=>String(v??"").trim();
function decode(s:string){return clean(s).replace(/&amp;/g,"&").replace(/&#x2013;|&#8211;/gi,"–").replace(/&#x27;|&#39;/gi,"'").replace(/&quot;/g,'"').replace(/&nbsp;/g," ");}
const DLI="";const provider:any={};
const parts=text.split('<div class="jsfilter-row');const dedup=new Map<string,any>();let rawRows=0,closedRows=0,conflicts=0;for(const part of parts){const status=part.match(/data-field-program-status\s*=\s*"([^"]+)"/)?.[1];const m=part.match(/<a href="([^"]+)">([^<]+) - ([A-Za-z0-9]+)<\/a>/);if(!m)continue;rawRows++;if(status!=="open"){closedRows++;continue;}const code=clean(m[3]),title=decode(m[2]);if(!code||!title){conflicts++;continue;}const prior=dedup.get(code);if(prior&&prior.course_title!==title){conflicts++;continue;}dedup.set(code,{provider_code:DLI,provider_name:provider.canonical_name||"Mohawk College",local_program_id:code,course_title:title,issuing_authority:"Mohawk College"});}
return [...dedup.values()];
}

// layer1-ca-niagara-catalogue
export function ref_niagara(html: string): any[] {
const t=(x:any)=>String(x??"").trim();
const DLI="";
const m=new Map<string,any>();let conflicts=0;for(const x of html.split('<div class="single-program"').slice(1)){const id=t(x.match(/<h4>\s*<a href="https:\/\/www\.niagaracollege\.ca\/([0-9A-Za-z]+)"/)?.[1]),code=t(x.match(/<span>Code:<\/span>\s*([0-9A-Za-z]+)\s+P[0-9A-Za-z]+/)?.[1]),title=t(x.match(/<h4>\s*<a[^>]*>([^<]+)<\/a>/s)?.[1]).replace(/&amp;/g,"&");if(!id||!title)continue;const st=new Set([...x.matchAll(/class="status ([OWSC])"/g)].map(z=>z[1]));const lc=st.has("O")||st.has("W")?"active":st.has("S")?"suspended":st.has("C")?"inactive":"unknown";if(m.has(id)&&m.get(id).course_title!==title){conflicts++;continue;}m.set(id,{provider_code:DLI,provider_name:"Niagara College Canada",local_program_id:id,course_title:title,issuing_authority:"Niagara College Canada",lifecycle_status:lc,regional_reg_scheme:"niagara_published_program_code",regional_reg_code:code});}
return [...m.values()];
}

// layer1-ca-seneca-catalogue
export function ref_seneca(html: string): any[] {
const t=(x:any)=>String(x??"").trim();
function dec(s:string){return t(s).replace(/&amp;/g,"&").replace(/&nbsp;/g," ").replace(/&#x2013;|&#8211;/gi,"–").replace(/&#x27;|&#39;/gi,"'").replace(/&quot;/g,'"');}
const DLI="";
const re=/<li><a href="\/programs\/([^/]+)\/">([^<]+)<\/a><\/li>/g,m=new Map<string,any>();let z,conflicts=0;while((z=re.exec(html))!==null){const slug=t(z[1]),label=dec(z[2]),cm=label.match(/\(([A-Za-z0-9]+)\)\s*$/);if(!cm)continue;const code=t(cm[1]),title=t(label.replace(/\s*\([A-Za-z0-9]+\)\s*$/,""));if(!code||!title)continue;const prior=m.get(code);if(prior&&prior.course_title!==title){conflicts++;continue;}m.set(code,{provider_code:DLI,provider_name:"Seneca College",local_program_id:code,course_title:title,issuing_authority:"Seneca Polytechnic",lifecycle_status:"unknown",source_slug:slug});}
return [...m.values()];
}

// layer1-ca-sheridan-programs
export function ref_sheridan(text: string): any[] {
const t=(x:any)=>String(x??"").trim();
function dec(s:string){return t(s).replace(/&amp;/g,"&").replace(/&#x2013;|&#8211;/gi,"–").replace(/&#x27;|&#39;/gi,"'").replace(/&quot;/g,'"').replace(/&nbsp;/g," ");}
function titleOf(h:string){return dec(h.match(/<a[^>]*title="([^"]+)"/)?.[1]||h.match(/<h3><a[^>]*>([^<]+)<\/a>/)?.[1]||"");}
const DLI="";const {all,active:act}=JSON.parse(text);
if(!Array.isArray(all.Results)||!Array.isArray(act.Results))throw new Error("Sheridan payload invalid");const active=new Set(act.Results.map((x:any)=>t(x.Id))),m=new Map<string,any>();let conflicts=0;for(const x of all.Results){const id=t(x.Id),title=titleOf(t(x.Html));if(!id||!title)continue;const prior=m.get(id);if(prior&&prior.course_title!==title){conflicts++;continue;}m.set(id,{provider_code:DLI,provider_name:"Sheridan College",local_program_id:id,course_title:title,issuing_authority:"Sheridan College",lifecycle_status:active.has(id)?"active":"inactive"});}
return [...m.values()];
}

// layer1-ca-stclair-programs
export function ref_stclair(html: string): any[] {
const t=(x:any)=>String(x??"").trim();
function clean(s:string){return t(s).replace(/<[^>]+>/g,"").replace(/\s+/g," ").replace(/&amp;/g,"&").replace(/&#039;|&#39;|&#x27;/gi,"'").replace(/&quot;/g,'"').replace(/&#8211;|&#x2013;/gi,"–");}
const DLI="";
const m=new Map<string,any>(),availability={open:0,closed:0,waitlisted:0};for(const part of html.split('<div class="program">').slice(1)){const sm=part.match(/program-status--(open|closed|waitlisted)/i),tm=part.match(/<a href="[^"]+"[^>]*>([\s\S]*?)<small/i),cm=part.match(/<small[^>]*>\s*-\s*([A-Za-z0-9-]+)/i);if(!sm||!tm||!cm)continue;const av=sm[1].toLowerCase() as keyof typeof availability,code=t(cm[1]).toUpperCase(),title=clean(tm[1]);if(!code||!title)continue;const prior=m.get(code);if(prior&&prior.course_title!==title)throw new Error(`St Clair conflicting programme code ${code}`);availability[av]++;m.set(code,{provider_code:DLI,provider_name:"St. Clair College",local_program_id:code,course_title:title,issuing_authority:"St. Clair College",lifecycle_status:"active",intake_availability:av});}
return [...m.values()];
}

// layer1-ca-live
export function ref_ircc_dli(html: string): any[] {
const clean = (v: unknown) => String(v ?? "").replace(/\s+/g, " ").trim();
const decode = (v: string) => clean(v
  .replace(/&nbsp;/g, " ")
  .replace(/&amp;/g, "&")
  .replace(/&quot;/g, '"')
  .replace(/&#39;|&apos;/g, "'")
  .replace(/&ndash;|&#8211;/g, "–")
  .replace(/&mdash;|&#8212;/g, "—")
  .replace(/<[^>]*>/g, " "));
function parseDliProviders(html: string) {
  const providers = new Map<string, any>();
  const rows = html.match(/<tr\b[\s\S]*?<\/tr>/gi) || [];
  for (const row of rows) {
    const cells = [...row.matchAll(/<t[dh]\b[^>]*>([\s\S]*?)<\/t[dh]>/gi)].map(m => decode(m[1]));
    if (cells.length < 3) continue;
    const joined = cells.join(" | ");
    const dli = joined.match(/\bO\d{10,15}\b/)?.[0];
    if (!dli) continue;
    const dliIndex = cells.findIndex(c => c.includes(dli));
    const providerName = dliIndex > 0 ? clean(cells[dliIndex - 1]) : "";
    if (!providerName || /DLI name|Institution/i.test(providerName)) continue;
    const province = dliIndex > 1 ? clean(cells[dliIndex - 2]) : null;
    const city = dliIndex >= 0 && cells[dliIndex + 1] ? clean(cells[dliIndex + 1]) : null;
    const campus = dliIndex >= 0 && cells[dliIndex + 2] ? clean(cells[dliIndex + 2]) : null;
    const publicPrivate = cells.find(c => /Public institution|Private institution/i.test(c)) || null;
    const current = providers.get(dli) || {
      provider_code: dli,
      provider_name: providerName,
      province,
      cities: new Set<string>(),
      campuses: new Set<string>(),
      public_private: publicPrivate,
    };
    if (city) current.cities.add(city);
    if (campus) current.campuses.add(campus);
    providers.set(dli, current);
  }
  return [...providers.values()].map(p => ({
    provider_code: p.provider_code,
    provider_name: p.provider_name,
    province: p.province,
    cities: [...p.cities],
    campuses: [...p.campuses],
    public_private: p.public_private,
  })).sort((a, b) => a.provider_code.localeCompare(b.provider_code));
}
return parseDliProviders(html);
}

// layer1-ca-provider-geography
export function ref_ircc_geo(html: string): any[] {
const t=(x:any)=>String(x??"").replace(/\s+/g," ").trim(),dec=(s:string)=>t(s.replace(/&nbsp;/g," ").replace(/&amp;/g,"&").replace(/&quot;/g,'"').replace(/&#39;|&apos;/g,"'").replace(/<[^>]*>/g," "));
function parse(html:string){const m=new Map<string,any>();for(const row of html.match(/<tr\b[\s\S]*?<\/tr>/gi)||[]){const cells=[...row.matchAll(/<t[dh]\b[^>]*>([\s\S]*?)<\/t[dh]>/gi)].map(x=>dec(x[1]));if(cells.length<3)continue;const dli=cells.join(" | ").match(/\bO\d{10,15}\b/)?.[0];if(!dli)continue;const q=cells.findIndex(x=>x.includes(dli)),name=q>0?t(cells[q-1]):"";if(!name||/DLI name|Institution/i.test(name))continue;const province=q>1?t(cells[q-2]):null,city=q>=0&&cells[q+1]?t(cells[q+1]):null,campus=q>=0&&cells[q+2]?t(cells[q+2]):null;const x=m.get(dli)||{provider_code:dli,provider_name:name,province,cities:new Set<string>(),campuses:new Set<string>()};if(city)x.cities.add(city);if(campus)x.campuses.add(campus);m.set(dli,x)}return[...m.values()].map(x=>({...x,cities:[...x.cities],campuses:[...x.campuses]})).sort((a,b)=>a.provider_code.localeCompare(b.provider_code))}
return parse(html);
}
