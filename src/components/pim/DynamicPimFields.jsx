import React,{useEffect,useMemo,useState}from'react'
import{api}from'../../data/supabase'
import{dynamicCourseAttributes,hasRenderablePimValues,pimDisplayValue,valuesByAttribute}from'../../domain/pim'

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
 const optionLabels=useMemo(()=>{
  const map=new Map((options||[]).map(x=>[`${x.attribute_id}:${x.code}`,x.label||x.code]))
  for(const value of values||[])for(const[code,label]of Object.entries(value?.option_labels||{}))map.set(`${value.attribute_id}:${code}`,String(label))
  return map
 },[options,values])
 const rows=useMemo(()=>definitions.map(attribute=>{const matches=grouped.get(attribute.code)||grouped.get(attribute.id)||[];const rendered=matches.map(value=>{const display=pimDisplayValue(attribute,value,optionLabels);return display==null?null:text(display)}).filter(Boolean);return rendered.length?{attribute,rendered}:null}).filter(Boolean),[definitions,grouped,optionLabels])
 if(!enabled||!family||rows.length===0)return null
 return <section className="m-detail-section cf-section" data-pim-dynamic-fields><div className="cf-section-title"><h3>{family.name||'Additional PIM attributes'}</h3></div><div className="m-detail-grid">{rows.map(({attribute,rendered})=><div className="cf-field" key={attribute.id}><div className="cf-field-label"><span>{attribute.name}</span></div><div className="cf-field-value">{rendered.join(', ')}</div></div>)}</div></section>
}
