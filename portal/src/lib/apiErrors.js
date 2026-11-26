// Plain-language errors for the portal's database calls. Pure: no browser or network code, so a spec can run it directly.
export class ApiError extends Error {
  constructor(kind, message) { super(message); this.kind = kind }
}

const PLATFORM_PREFIX = /^(INVALID_INPUT|SAVED_LIMIT):\s*/

export function toApiError(error) {
  const text = String(error?.message || '')
  const code = String(error?.code || '')
  if (code === 'PGRST202' || code === '42883' || /could not find the function|schema cache/i.test(text)) {
    return new ApiError('missing', 'This part of the platform is not switched on yet.')
  }
  if (code === 'P0002' || /course not found/i.test(text)) return new ApiError('notfound', 'This course is no longer listed, so its details are not shown.')
  if (PLATFORM_PREFIX.test(text)) return new ApiError(text.startsWith('SAVED_LIMIT') ? 'limit' : 'input', text.replace(PLATFORM_PREFIX, ''))
  if (code === '42501' || /permission denied|not allowed|insufficient/i.test(text)) {
    return new ApiError('access', 'Your role does not include this. Ask a Platform Admin if you need it.')
  }
  if (/failed to fetch|network|load failed/i.test(text)) return new ApiError('network', 'We could not reach StudySearch. Check your connection and try again.')
  return new ApiError('failed', 'Something went wrong on our side. Please try again in a moment.')
}
