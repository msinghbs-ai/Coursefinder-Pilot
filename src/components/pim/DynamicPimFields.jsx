import React,{useEffect,useMemo,useState}from'react'
import{api}from'../../data/supabase'
import{dynamicCourseAttributes,hasRenderablePimValues,pimValue,valuesByAttribute}from'../../domain/pim'

const text=value=>{
 if(value==null)return'—'
 if(Array.isArray(value))return value.map(text).join(', ')
 if(typeof value==='object')return JSON.stringify(value)
 if(typeof value==='boolean')return value?'Yes':'No'
 return String(value)
}

export default function DynamicPimFields({entityType='course',familyId=null,values=[]}){
 const[attributes,setAttributes]=useState([]),[families,setFamilies]=useState([]),[options,setOptions]=useState([])
 const enabled=Boolean(familyId)&&hasRenderablePimValues(values)
 useEffect(()=>{let live=true;if(!enabled)return()=>{live=false};Promise.all([api.attributes(),api.attributeFamilies(),api.attributeOptions()]).then(([a,f,o])=>{if(!live)return;setAttributes(a||[]);setFamilies(f||[]);setOptions(o||[])}).catch(()=>{if(live){setAttributes([]);setFamilies([]);setOptions([])}});return()=>{live=false}},[enabled])
 const family=useMemo(()=>families.find(x=>String(x.id)===String(familyId))||null,[families,familyId])
 const definitions=useMemo(()=>entityType==='course'?dynamicCourseAttributes(attributes):attributes.filter(x=>x.entity_type===entityType&&(!x.status||x.status==='active')),[attributes,entityType])
 const grouped=useMemo(()=>valuesByAttribute(values||[]),[values])
 const optionLabels=useMemo(()=>new Map((options||[]).map(x=>[`${x.attribute_id}:${x.code}`,x.label||x.code])),[options])
 const rows=useMemo(()=>definitions.map(attribute=>{const matches=grouped.get(attribute.code)||grouped.get(attribute.id)||[];const rendered=matches.map(value=>{const raw=pimValue(value);if(raw==null)return null;if(value.value_code!=null)return optionLabels.get(`${attribute.id}:${value.value_code}`)||text(raw);return text(raw)}).filter(Boolean);return rendered.length?{attribute,rendered}:null}).filter(Boolean),[definitions,grouped,optionLabels])
 if(!enabled||!family||rows.length===0)return null
 return <section className="m-detail-section cf-section" data-pim-dynamic-fields><div className="cf-section-title"><h3>{family.name||'Additional PIM attributes'}</h3></div><div className="m-detail-grid">{rows.map(({attribute,rendered})=><div className="cf-field" key={attribute.id}><div className="cf-field-label"><span>{attribute.name}</span></div><div className="cf-field-value">{rendered.join(', ')}</div></div>)}</div></section>
}
