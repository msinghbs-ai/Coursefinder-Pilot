// Guards: REQ-105 (Platform Admin consolidated batch, 22 Nov 2026 14:22 AEDT): the Courses page opens with one list read, already carrying the person's remembered search, filters and sort
// s974: measured signed in on 22 Nov 2026, the Courses page sent two list reads on opening: the defaults first, then the person's remembered
// filters and sort a moment later, so the second waited behind the first. The list now waits for the remembered state, and for a search
// still being typed, before it reads.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MAIN = fs.readFileSync('src/mature-main.jsx', 'utf8')
const KIT = fs.readFileSync('src/ui-kit.jsx', 'utf8')

test('the catalogue list reads once its remembered state is loaded, and not mid-search', () => {
  expect(KIT).toContain('return [state,update,reset,Boolean(key&&key===loadedKey)]')
  expect(MAIN).toContain("const[remembered,remember,,rememberedReady]=useRememberedState(type,{query:'',filters:{},filterLabels:{},advanced:type==='course'")
  expect(MAIN).toContain("useEffect(()=>{if(!rememberedReady){setBusy(true);return}if(debounced!==query)return;let live=true;setBusy(true);adminRead(cfg.operation,args)")
  expect(MAIN).toContain('},[cfg.operation,JSON.stringify(args),rememberedReady])')
})
