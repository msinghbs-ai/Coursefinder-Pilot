// The Admin menu: sections in the route table's order; a page appears only when the rank may open it. Pure (no stylesheet import), so the shell,
// the specs and the guide check read the same list.
export function menuFor({ sections, pages, rank, canOpen }) {
  return sections.map(s => ({ label: s.label, items: s.pages.filter(k => canOpen(k, rank)).map(k => ({ key: k, label: pages[k].label })) })).filter(s => s.items.length)
}
