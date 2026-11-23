// v1.1 Admin shell (rank 3 and above; v1.2 plan, Slice 1 step 1). The frame (top bar and left menu) is drawn here from the same route table that
// produces docs/UI-MAP.md (SECTIONS and PAGES in src/nav-map.js, filtered by the person's rank). The Admin screens that are not yet ported open
// inside it unchanged; each later port replaces one of them. Only the two ui-v1 stylesheets are imported (never a legacy file).
import './tokens.css'
import './ui-kit.css'

/** The menu: sections in the route table's order; a page appears only when the rank may open it. Pure, so the guide check can read the same list. */
export function menuFor({ sections, pages, rank, canOpen }) {
  return sections.map(s => ({ label: s.label, items: s.pages.filter(k => canOpen(k, rank)).map(k => ({ key: k, label: pages[k].label })) })).filter(s => s.items.length)
}

export default function AdminShell({ sections, pages, rank, canOpen, hrefFor, active, roleLabel, email, version, open, setOpen, onGo, onSignOut, children }) {
  const menu = menuFor({ sections, pages, rank, canOpen })
  return <div className={`ui-shell ui-admin${open ? ' is-open' : ''}`} data-ui-admin-shell>
    <header className="ui-topbar">
      <button type="button" className="ui-btn ui-btn-sm ui-nav-toggle" aria-expanded={open} aria-label="Open menu" onClick={() => setOpen(v => !v)}>Menu</button>
      <a className="ui-brand" href={hrefFor('dashboard')} onClick={e => { e.preventDefault(); setOpen(false); onGo('dashboard') }}>StudySearch</a>
      {version && <span className="ui-brand-version">PIM Admin v{version}</span>}
      <span className="ui-topbar-spacer" />
      <span className="ui-topbar-user" title={email}>{roleLabel}{email ? ` · ${email}` : ''}</span>
      <button type="button" className="ui-btn ui-btn-sm" title="Sign out" onClick={onSignOut}>Sign out</button>
    </header>
    <nav className="ui-nav" aria-label="Main menu" data-ui-admin-nav>
      {menu.map(s => <div key={s.label || 'home'} data-nav-group>{s.label && <div className="ui-nav-label">{s.label}</div>}
        {s.items.map(i => <a key={i.key} href={hrefFor(i.key)} aria-current={i.key === active ? 'page' : 'false'} data-nav-page={i.key} onClick={e => { e.preventDefault(); setOpen(false); onGo(i.key) }}>{i.label}</a>)}</div>)}
    </nav>
    <div className="ui-admin-content">{children}</div>
  </div>
}
