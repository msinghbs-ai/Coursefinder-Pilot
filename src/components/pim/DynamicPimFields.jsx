import React,{useEffect,useMemo,useState}from'react'
import{api}from'../../data/supabase'
import{dynamicCourseAttributes,hasRenderablePimValues,pimDisplayValue,pimOptionLabelsForValue,pimScopeLabel,valuesByAttribute,valuesByScope}from'../../domain/pim'

const text=value=>{
 if(value==null)return'—'
 if(Array.isArray(value))return value.map(text).join(', ')
 if(typeof value==='object')return JSON.stringify(value)
 if(typeof value==='boolean')return value?'Yes':'No'
 return String(value)
}

export default function DynamicPimFields({entityType='course',familyId=null,familyName='',values=[]}){
 const[attributes,setAttributes]=useState([]),[families,setFamilies]=useState([]),[options,setOptions]=useState([])
 const enabled=Boolean(familyId)&&hasRenderablePimValues(values)
 const embeddedDefinitions=useMemo(()=>{
  const byId=new Map()
  for(const value of values||[]){
   if(!value?.attribute_id||!value?.attribute_code||!value?.attribute_name||!value?.attribute_data_type)continue
   if(!byId.has(value.attribute_id))byId.set(value.attribute_id,{id:value.attribute_id,code:value.attribute_code,name:value.attribute_name,entity_type:entityType,data_type:value.attribute_data_type,is_multivalue:Boolean(value.attribute_is_multivalue),display_order:value.attribute_display_order??0,status:'active'})
  }
  return[...byId.values()]
 },[values,entityType])
 const needsFallback=enabled&&embeddedDefinitions.length===0
 useEffect(()=>{let live=true;if(!needsFallback)return()=>{live=false};Promise.all([api.attributes(),api.attributeFamilies(),api.attributeOptions()]).then(([a,f,o])=>{if(!live)return;setAttributes(a||[]);setFamilies(f||[]);setOptions(o||[])}).catch(()=>{if(live){setAttributes([]);setFamilies([]);setOptions([])}});return()=>{live=false}},[needsFallback])
 const family=useMemo(()=>familyName?{id:familyId,name:familyName}:families.find(x=>String(x.id)===String(familyId))||{id:familyId,name:'Additional PIM attributes'},[families,familyId,familyName])
 const sourceDefinitions=embeddedDefinitions.length?embeddedDefinitions:attributes
 const definitions=useMemo(()=>entityType==='course'?dynamicCourseAttributes(sourceDefinitions):sourceDefinitions.filter(x=>x.entity_type===entityType&&(!x.status||x.status==='active')),[sourceDefinitions,entityType])
 const grouped=useMemo(()=>valuesByAttribute(values||[]),[values])
 const fallbackOptionLabels=useMemo(()=>new Map((options||[]).map(x=>[`${x.attribute_id}:${x.code}`,x.label||x.code])),[options])
 const rows=useMemo(()=>definitions.flatMap(attribute=>{
  const matches=grouped.get(attribute.code)||grouped.get(attribute.id)||[]
  return[...valuesByScope(matches).values()].map(partition=>{
   const rendered=partition.map(value=>{const display=pimDisplayValue(attribute,value,pimOptionLabelsForValue(value,fallbackOptionLabels));return display==null?null:text(display)}).filter(Boolean)
   if(!rendered.length)return null
   const scope=pimScopeLabel(partition[0])
   return{attribute,rendered,scope,key:`${attribute.id}:${partition[0]?.locale??''}:${partition[0]?.channel_code??''}`}
  }).filter(Boolean)
 }),[definitions,grouped,fallbackOptionLabels])
 if(!enabled||!family||rows.length===0)return null
 return <section className="m-detail-section cf-section" data-pim-dynamic-fields><div className="cf-section-title"><h3>{family.name||'Additional PIM attributes'}</h3></div><div className="m-detail-grid">{rows.map(({attribute,rendered,scope,key})=><div className="cf-field" key={key} data-pim-locale={scope?undefined:''}><div className="cf-field-label"><span>{attribute.name}{scope?` · ${scope}`:''}</span></div><div className="cf-field-value">{rendered.join(', ')}</div></div>)}</div></section>
}
