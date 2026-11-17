import{pickHtmlTable}from'../../supabase/functions/_shared/cf247-html-table.js'
// CF-247 Layer 1 induction wizard: read a small sample file in the browser (no library). Only the column names and the first rows are kept.
// a pasted or uploaded delimited sample: the header row and the first rows (quotes handled; no library)
export function parseDelimited(text,keep=20){
  const first=String(text||'').split(/\r?\n/,1)[0]||'',delim=(first.match(/\t/g)||[]).length>(first.match(/,/g)||[]).length?'\t':(first.match(/;/g)||[]).length>(first.match(/,/g)||[]).length?';':','
  const rows=[];let row=[],cell='',q=false
  const s=String(text||'')
  for(let i=0;i<s.length;i++){const c=s[i]
    if(q){if(c==='"'){if(s[i+1]==='"'){cell+='"';i++}else q=false}else cell+=c}
    else if(c==='"')q=true
    else if(c===delim){row.push(cell);cell=''}
    else if(c==='\n'||c==='\r'){if(c==='\r'&&s[i+1]==='\n')i++;row.push(cell);cell='';if(row.some(x=>x!==''))rows.push(row);row=[]}
    else cell+=c}
  row.push(cell);if(row.some(x=>x!==''))rows.push(row)
  if(!rows.length)return null
  const columns=rows[0].map((c,i)=>String(c||'').trim()||`column_${i+1}`)
  return{columns,rows:rows.slice(1,1+keep),total_rows:rows.length-1}
}
// Track B (18 Nov 2026): a saved web page; the table with the most rows, read by the same code the dry run uses
export function parseHtmlSample(text,keep=20){
  try{const t=pickHtmlTable(text,keep);if(!t)return null
    return{columns:t.headers,rows:t.arrays.map(r=>t.headers.map((_,i)=>String(r[i]??''))),total_rows:t.total_rows,table_index:t.table_index,header_row:t.header_row,tables:t.tables.length}}
  catch{return null}
}
export function parseSample(name,text,keep=20){
  if(/\.html?$/i.test(name||'')||/^\s*(<!doctype html|<html|<table)/i.test(text||''))return parseHtmlSample(text,keep)
  if(/\.json$/i.test(name||'')||/^\s*[\[{]/.test(text||'')){try{const j=JSON.parse(text);const list=Array.isArray(j)?j:Array.isArray(j?.data)?j.data:Array.isArray(j?.results)?j.results:Array.isArray(j?.items)?j.items:null
    if(list&&list.length&&typeof list[0]==='object'){const columns=[...new Set(list.slice(0,50).flatMap(o=>Object.keys(o||{})))];return{columns,rows:list.slice(0,keep).map(o=>columns.map(c=>o?.[c]==null?'':typeof o[c]==='object'?JSON.stringify(o[c]):String(o[c]))),total_rows:list.length}}}catch{/* not JSON: read it as delimited text */}}
  return parseDelimited(text,keep)
}
