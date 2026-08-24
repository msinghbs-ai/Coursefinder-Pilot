import {supabase} from './lib/supabase'

export async function resolveCourseScalar(courseId,fieldCode,value,reason){
  const{data,error}=await supabase.rpc('layer4_course_scalar_resolve',{
    p_course_id:courseId,
    p_field_code:fieldCode,
    p_value:value,
    p_reason:reason,
  })
  if(error)throw error
  return data
}
