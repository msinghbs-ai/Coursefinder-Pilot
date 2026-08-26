import fs from 'node:fs/promises'
import path from 'node:path'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

const ARTIFACT_DIR=path.resolve('uat-artifacts')
const wait=ms=>new Promise(r=>setTimeout(r,ms))
const safe=v=>String(v).toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,80)

async function screenshot(page,name){const file=path.join(ARTIFACT_DIR,`${page.context()._options?.isMobile?'mobile':'desktop'}-audit-${safe(name)}.png`);await page.screenshot({path:file,fullPage:true});return path.basename(file)}
async function closeVisibleDialog(page){const dialogs=page.locator('[role="dialog"]:visible');if(await dialogs.count()){const d=dialogs.last();const close=d.getByRole('button',{name:/close/i}).first();if(await close.count())await close.click().catch(()=>{});else await page.keyboard.press('Escape').catch(()=>{});await wait(150)}}

async function visibleNavigation(page){return page.locator('.m-nav').evaluate(nav=>[...nav.querySelectorAll('.m-nav-group')].map(g=>({group:g.querySelector('.m-nav-label')?.textContent?.trim()||'',items:[...g.querySelectorAll('button.m-nav-item')].filter(b=>getComputedStyle(b).display!=='none'&&b.offsetParent!==null).map(b=>b.querySelector('span')?.textContent?.trim()||b.textContent.trim())})).filter(x=>x.group&&x.items.length))}

async function openMenuItem(page,label){const item=page.locator('button.m-nav-item').filter({hasText:label}).first();await expect(item).toBeVisible({timeout:45_000});const box=await item.boundingBox();const vp=page.viewportSize();if(box&&vp&&(box.y<0||box.y+box.height>vp.height)){const mobile=page.locator('.m-mobile-menu');if(await mobile.isVisible().catch(()=>false)){await mobile.click();await expect(page.locator('.m-sidebar')).toHaveClass(/is-open/)}await item.scrollIntoViewIfNeeded()}const started=Date.now();await item.click();await wait(650);return Date.now()-started}

async function captureSurface(page,label){const elapsed_ms=await openMenuItem(page,label);const dialog=page.locator('[role="dialog"]:visible').last();const hasDialog=await dialog.count()>0;const surface=hasDialog?dialog:page.locator('.m-main');const text=(await surface.innerText().catch(()=>'' )).replace(/\s+/g,' ').trim();const heading=hasDialog?await dialog.locator('h1,h2,h3').first().innerText().catch(()=>label):await page.locator('.m-topbar h1').innerText().catch(()=>label);const image=await screenshot(page,label);const result={label,elapsed_ms,route:page.url().split('#')[1]||'dashboard',surface:hasDialog?'dialog':'page',heading,text_sample:text.slice(0,2200),screenshot:image};if(hasDialog)await closeVisibleDialog(page);return result}

test.describe('M2.4 navigation/content audit @deployed',()=>{
 test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await fs.mkdir(ARTIFACT_DIR,{recursive:true});await writeRunEnvironment({suite:'m2-4-navigation-content-audit',change_control:'CF-CHG-20260826-040'})})
 test('capture visible menu, page content, navigation timing and screenshots',async({page},testInfo)=>{const runtime=observeRuntime(page);try{await loginAsUatUser(page);const navigation=await visibleNavigation(page);const pages=[];for(const group of navigation){for(const label of group.items){if(label==='Dashboard'){pages.push(await captureSurface(page,label));continue}pages.push(await captureSurface(page,label))}}const payload={captured_at:new Date().toISOString(),project:testInfo.project.name,viewport:page.viewportSize(),navigation,pages};const file=path.join(ARTIFACT_DIR,`${testInfo.project.name}-navigation-content-audit.json`);await fs.writeFile(file,JSON.stringify(payload,null,2));await testInfo.attach('navigation-content-audit',{path:file,contentType:'application/json'});expect(navigation.some(x=>x.group==='Data Operations')).toBeTruthy();expect(navigation.some(x=>x.group==='Help & Guides')).toBeTruthy()}finally{await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}})
})
