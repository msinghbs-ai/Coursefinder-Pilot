import { useCallback, useEffect, useState } from 'react'
import { rpc } from './api.js'

// The person's own shortlist (Counsellor and above). The limits are database settings and arrive with the list.
export function useSaved(enabled) {
  const [s, setS] = useState({ loading: enabled, error: '', items: [], savedMax: null, compareMax: null })
  const [busy, setBusy] = useState('')
  const [message, setMessage] = useState('')

  const refresh = useCallback(() => rpc('portal_saved_list_v1')
    .then(r => setS({ loading: false, error: '', items: r.items || [], savedMax: r.saved_max, compareMax: r.compare_max }))
    .catch(e => setS(o => ({ ...o, loading: false, error: e.message }))), [])

  useEffect(() => { if (enabled) refresh(); else setS(o => ({ ...o, loading: false })) }, [enabled, refresh])

  const ids = new Set(s.items.map(i => i.course_id))
  const toggle = useCallback(async (courseId, next) => {
    setBusy(courseId); setMessage('')
    try { await rpc('portal_saved_set_v1', { p_course_id: courseId, p_saved: next }); await refresh() }
    catch (e) { setMessage(e.message) }
    finally { setBusy('') }
  }, [refresh])

  return { ...s, ids, toggle, busy, message, clearMessage: () => setMessage(''), refresh }
}
