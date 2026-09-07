from pathlib import Path

for path in ['index.html','src/mature-main.jsx','src/pim-version-entry.js','tests/uat/m245-ui-improvements-contract.spec.mjs']:
    p=Path(path)
    s=p.read_text().replace('2.15.74','2.15.75')
    p.write_text(s)

p=Path('src/release-currentness-entry.js')
s=p.read_text()
head="""const VERSION='2.15.75'\nconst RELEASE={\n  version:VERSION,\n  date:'7 Sep 2026',\n  title:'Statistics ranking edition controls and dataset drill-down',\n  changes:[\n    'Statistics & Rankings now gives QS and THE independent edition dropdowns backed by their retained accepted editions.',\n    'Ranking import controls have been removed from Statistics & Rankings; import management remains only in Administration → Sources & Imports.',\n    'QS/THE Open Dataset now uses a native React drill-down with governed ranking_filters and ranking_observations reads, edition switching, search, sorting, paging and Evidence access.',\n    'Provider Compare keeps its independent QS/THE selectors and sticky University/Provider identity headers. No database, ranking-data, publication, Search, Website/Zoho or Production semantics changed.'\n  ]\n}\n"""
idx=s.index('let pending=false')
p.write_text(head+s[idx:])

old=Path('tests/uat/m245-v2-15-74-release-currentness-deployed.spec.mjs')
if old.exists():
    s=old.read_text().replace('2.15.74','2.15.75').replace('m245-v2-15-74-release-currentness','m245-v2-15-75-release-currentness').replace('CF-CHG-20260907-243','CF-CHG-20260907-244').replace('Compare ranking year controls and frozen university headers','Statistics ranking edition controls and dataset drill-down')
    # The browser title should now be fully synchronized as well.
    s=s.replace("/Coursefinder PIM Admin v2\\.15\\.73/","/Coursefinder PIM Admin v2\\.15\\.75/")
    new=Path('tests/uat/m245-v2-15-75-release-currentness-deployed.spec.mjs')
    new.write_text(s)
    old.unlink()
