import { useEffect, useState } from 'react'
import { rpc } from './api.js'

// The Course details read (portal_course_detail_v1, s1214). The words and formats are in courseDetailFormat.js.
export function useCourseDetail(courseId, enabled) {
  const [s, setS] = useState({ loading: false, error: '', unavailable: false, gone: false, data: null })
  useEffect(() => {
    if (!enabled || !courseId) return undefined
    let live = true
    setS({ loading: true, error: '', unavailable: false, gone: false, data: null })
    rpc('portal_course_detail_v1', { p_course_id: courseId })
      .then(data => { if (live) setS({ loading: false, error: '', unavailable: false, gone: false, data }) })
      .catch(e => { if (live) setS({ loading: false, error: e.kind === 'notfound' ? '' : e.message, unavailable: e.kind === 'missing', gone: e.kind === 'notfound', data: null }) })
    return () => { live = false }
  }, [courseId, enabled])
  return s
}
