from pathlib import Path

# mature host version
p=Path('src/mature-main.jsx'); s=p.read_text(); s=s.replace("const UI_VERSION='2.15.73'","const UI_VERSION='2.15.74'",1); p.write_text(s)

# browser title
p=Path('index.html'); s=p.read_text().replace('Coursefinder PIM Admin v2.15.73','Coursefinder PIM Admin v2.15.74'); p.write_text(s)

# release currentness reconciler
p=Path('src/release-currentness-entry.js'); s=p.read_text(); s=s.replace("const VERSION='2.15.73'","const VERSION='2.15.74'",1); s=s.replace("title:'Fluid catalogues, ranking datasets and Provider comparison'","title:'Compare ranking year controls and frozen university headers'",1); start=s.index('  changes:['); end=s.index('  ]\n}',start); changes="""  changes:[
    'Provider Compare now presents QS and THE as independent ranking sections, each with its own edition selector and Multi-year option.',
    'The shared Current snapshot / Multi-year trend control has been removed from QILT/PRISMS comparison; QILT retains an explicit year selector.',
    'University/provider identity headers are explicitly sticky across QILT, PRISMS and ranking comparison surfaces while comparison content scrolls.',
    'The focused source contract, frontend build/browser smoke and deployed Pilot UAT passed on 7 Sep 2026. No database, ranking, QILT/PRISMS grain, publication, Search, Website/Zoho or Production semantics changed.'
"""; s=s[:start]+changes+s[end:]; p.write_text(s)

# release list
p=Path('src/pim-version-entry.js'); s=p.read_text(); s=s.replace("const VERSION='2.15.73'","const VERSION='2.15.74'",1); marker='const RELEASES=[\n'; entry="  {version:'2.15.74',date:'7 Sep 2026',title:'Compare ranking year controls and frozen university headers',changes:['Provider Compare now presents QS and THE as independent ranking sections, each with its own edition selector and Multi-year option.','The shared Current snapshot / Multi-year trend control has been removed from QILT/PRISMS comparison; QILT retains an explicit year selector.','University/provider identity headers are explicitly sticky across QILT, PRISMS and ranking comparison surfaces while comparison content scrolls.','Focused source contract, frontend build/browser smoke and deployed Pilot UAT passed; no database, ranking, QILT/PRISMS grain, publication, Search, Website/Zoho or Production semantics changed.']},\n"; s=s.replace(marker,marker+entry,1); p.write_text(s)

# source contract version assertion
p=Path('tests/uat/m245-ui-improvements-contract.spec.mjs'); s=p.read_text().replace("const UI_VERSION='2.15.73'","const UI_VERSION='2.15.74'"); p.write_text(s)

# currentness deployed gate rename/update
old=Path('tests/uat/m245-v2-15-73-release-currentness-deployed.spec.mjs')
if old.exists():
    s=old.read_text().replace('v2.15.73','v2.15.74').replace('2.15.73','2.15.74').replace('m245-v2-15-73-release-currentness','m245-v2-15-74-release-currentness').replace('CF-CHG-20260907-242','CF-CHG-20260907-243')
    new=Path('tests/uat/m245-v2-15-74-release-currentness-deployed.spec.mjs'); new.write_text(s); old.unlink()
