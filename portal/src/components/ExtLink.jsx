import React from 'react'

// Every link that leaves the portal (a course page, a provider website, a scholarship page) goes through this one component, so each
// opens in a new tab and cannot reach back into the portal window. A link that is not a web address is not drawn at all.
// Guarded by the s1215 contract spec: no other element in the portal writes an outside address into an href.
export const isWebAddress = href => /^https?:\/\//i.test(String(href || '').trim())

export function ExtLink({ href, className, children, ...rest }) {
  if (!isWebAddress(href)) return null
  return <a {...rest} className={className} href={String(href).trim()} target="_blank" rel="noopener noreferrer">{children}</a>
}
