import {supabase} from './lib/supabase'

export async function resolveCourseScalar(courseId,fieldCode,value,reason){
  const{data,error}=await supabase.functions.invoke('layer4-course-resolve',{
    body:{course_id:courseId,field_code:fieldCode,value,reason},
  })
  if(error)throw error
  if(data?.error)throw new Error(data.error)
  return data
}
