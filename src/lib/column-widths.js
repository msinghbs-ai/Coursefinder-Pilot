// s1076: the saved column widths of the shared catalogue table, kept per browser (the choice only moves a column, so it is not shared).
// Lives outside src/ui-v1 so the ui-v1 views stay free of browser storage.
export const columnWidthsKey = id => `cf-colw:${id}`
export function readColumnWidths(id) { try { return JSON.parse(localStorage.getItem(columnWidthsKey(id)) || '{}') || {} } catch { return {} } }
export function writeColumnWidths(id, widths) { try { localStorage.setItem(columnWidthsKey(id), JSON.stringify(widths)) } catch { /* private mode: the widths last for the visit */ } }
