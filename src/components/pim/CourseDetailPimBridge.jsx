import React from'react'
import CourseDetailPolish from'../../CourseDetailPolish'
import DynamicPimFields from'./DynamicPimFields'

export default function CourseDetailPimBridge({data,navigate}){
 if(!data)return null
 const familyId=data.pim_family_id??data.pim?.family_id??null
 const values=data.pim_attribute_values??data.attribute_values??data.pim?.attribute_values??[]
 return <><CourseDetailPolish data={data} navigate={navigate}/><DynamicPimFields entityType="course" familyId={familyId} values={Array.isArray(values)?values:[]}/></>
}
