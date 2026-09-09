import fs from 'node:fs/promises'
import path from 'node:path'
import ts from 'typescript'
import { expect, test } from '@playwright/test'

type BrowserModule = {
  absolutePath: string
  repositoryPath: string
  source: string
  sourceFile: ts.SourceFile
}

type RoleGraph = Map<string, Set<string>>

const repositoryRoot = process.cwd()
const governedEvidenceTables = new Set([
  'pipeline.evidence_artifacts',
  'storage.objects',
])

async function readText(filePath: string): Promise<string> {
  return fs.readFile(filePath, 'utf8')
}

async function readMigrationSource(): Promise<string> {
  const directory = path.join(repositoryRoot, 'supabase', 'migrations')
  const names = (await fs.readdir(directory)).filter((name: string) => name.endsWith('.sql')).sort()
  const sources = await Promise.all(names.map(async (name: string): Promise<string> => {
    const source = await readText(path.join(directory, name))
    return `\n-- ${name}\n${source}`
  }))
  return sources.join('\n')
}

function scriptKind(filePath: string): ts.ScriptKind {
  if (/\.tsx$/i.test(filePath)) return ts.ScriptKind.TSX
  if (/\.jsx$/i.test(filePath)) return ts.ScriptKind.JSX
  if (/\.(?:mts|mjs)$/i.test(filePath)) return ts.ScriptKind.TS
  if (/\.(?:cts|cjs)$/i.test(filePath)) return ts.ScriptKind.TS
  if (/\.ts$/i.test(filePath)) return ts.ScriptKind.TS
  return ts.ScriptKind.JS
}

function parseSource(filePath: string, source: string): ts.SourceFile {
  return ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, scriptKind(filePath))
}

function moduleSpecifiers(sourceFile: ts.SourceFile): string[] {
  const values = new Set<string>()
  const visit = (node: ts.Node): void => {
    if ((ts.isImportDeclaration(node) || ts.isExportDeclaration(node))
      && node.moduleSpecifier
      && ts.isStringLiteralLike(node.moduleSpecifier)) {
      values.add(node.moduleSpecifier.text)
    }
    if (ts.isCallExpression(node) && node.arguments.length === 1 && ts.isStringLiteralLike(node.arguments[0])) {
      if (node.expression.kind === ts.SyntaxKind.ImportKeyword) values.add(node.arguments[0].text)
      if (ts.isIdentifier(node.expression) && node.expression.text === 'require') values.add(node.arguments[0].text)
    }
    ts.forEachChild(node, visit)
  }
  visit(sourceFile)
  return [...values]
}

async function existingFile(candidate: string): Promise<string | null> {
  try {
    const stat = await fs.stat(candidate)
    return stat.isFile() ? candidate : null
  } catch {
    return null
  }
}

async function resolveLocalModule(fromFile: string, specifier: string): Promise<string | null> {
  if (!specifier.startsWith('.') && !specifier.startsWith('/')) return null
  const base = specifier.startsWith('/')
    ? path.join(repositoryRoot, specifier.replace(/^\/+/, ''))
    : path.resolve(path.dirname(fromFile), specifier)
  const extensions = ['', '.ts', '.tsx', '.js', '.jsx', '.mts', '.cts', '.mjs', '.cjs']
  for (const extension of extensions) {
    const direct = await existingFile(`${base}${extension}`)
    if (direct) return direct
  }
  for (const extension of extensions.slice(1)) {
    const indexed = await existingFile(path.join(base, `index${extension}`))
    if (indexed) return indexed
  }
  throw new Error(`Unable to resolve local browser module ${specifier} imported from ${path.relative(repositoryRoot, fromFile)}`)
}

function htmlScriptSources(html: string): string[] {
  const sources: string[] = []
  for (const tag of html.match(/<script\b[^>]*>/gi) ?? []) {
    const match = tag.match(/\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i)
    if (match) sources.push(match[1] ?? match[2] ?? match[3] ?? '')
  }
  return sources
}

async function browserModuleGraph(): Promise<BrowserModule[]> {
  const html = await readText(path.join(repositoryRoot, 'index.html'))
  const queue: string[] = []
  for (const source of htmlScriptSources(html)) {
    if (!source.startsWith('/src/')) throw new Error(`Browser entry point outside governed /src tree: ${source}`)
    const resolved = await resolveLocalModule(path.join(repositoryRoot, 'index.html'), source)
    if (!resolved) throw new Error(`Browser entry point is not local: ${source}`)
    queue.push(resolved)
  }
  if (queue.length === 0) throw new Error('No browser module entry point found in index.html')

  const visited = new Set<string>()
  const modules: BrowserModule[] = []
  while (queue.length > 0) {
    const absolutePath = path.resolve(queue.shift() as string)
    if (visited.has(absolutePath)) continue
    visited.add(absolutePath)
    const repositoryPath = path.relative(repositoryRoot, absolutePath).replaceAll('\\', '/')
    if (repositoryPath.startsWith('../') || path.isAbsolute(repositoryPath)) {
      throw new Error(`Browser module resolves outside repository: ${absolutePath}`)
    }
    const source = await readText(absolutePath)
    const sourceFile = parseSource(repositoryPath, source)
    modules.push({ absolutePath, repositoryPath, source, sourceFile })
    for (const specifier of moduleSpecifiers(sourceFile)) {
      const resolved = await resolveLocalModule(absolutePath, specifier)
      if (resolved) queue.push(resolved)
    }
  }
  return modules
}

function executableSensitiveTokens(sourceFile: ts.SourceFile): string[] {
  const hits: string[] = []
  const visit = (node: ts.Node): void => {
    if (ts.isIdentifier(node) || ts.isStringLiteralLike(node)) {
      if (/SUPABASE.*SERVICE|SERVICE_ROLE/i.test(node.text)) hits.push(node.text)
    }
    ts.forEachChild(node, visit)
  }
  visit(sourceFile)
  return hits
}

function supabaseConstructorImports(sourceFile: ts.SourceFile): Set<string> {
  const names = new Set<string>()
  for (const statement of sourceFile.statements) {
    if (!ts.isImportDeclaration(statement)
      || !ts.isStringLiteralLike(statement.moduleSpecifier)
      || statement.moduleSpecifier.text !== '@supabase/supabase-js') continue
    const bindings = statement.importClause?.namedBindings
    if (!bindings) continue
    if (ts.isNamespaceImport(bindings)) names.add(`${bindings.name.text}.createClient`)
    if (ts.isNamedImports(bindings)) {
      for (const element of bindings.elements) {
        const imported = element.propertyName?.text ?? element.name.text
        if (imported === 'createClient') names.add(element.name.text)
      }
    }
  }
  return names
}

function constructorCalls(sourceFile: ts.SourceFile, constructorNames: Set<string>): ts.CallExpression[] {
  const calls: ts.CallExpression[] = []
  const visit = (node: ts.Node): void => {
    if (ts.isCallExpression(node)) {
      if (ts.isIdentifier(node.expression) && constructorNames.has(node.expression.text)) calls.push(node)
      if (ts.isPropertyAccessExpression(node.expression)
        && ts.isIdentifier(node.expression.expression)
        && constructorNames.has(`${node.expression.expression.text}.createClient`)
        && node.expression.name.text === 'createClient') calls.push(node)
    }
    ts.forEachChild(node, visit)
  }
  visit(sourceFile)
  return calls
}

function variableInitializers(sourceFile: ts.SourceFile): Map<string, ts.Expression> {
  const values = new Map<string, ts.Expression>()
  const visit = (node: ts.Node): void => {
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer) values.set(node.name.text, node.initializer)
    ts.forEachChild(node, visit)
  }
  visit(sourceFile)
  return values
}

function unwrapFallback(expression: ts.Expression): ts.Expression {
  if (ts.isParenthesizedExpression(expression)) return unwrapFallback(expression.expression)
  if (ts.isBinaryExpression(expression)
    && (expression.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken || expression.operatorToken.kind === ts.SyntaxKind.BarBarToken)) {
    return unwrapFallback(expression.left)
  }
  return expression
}

function normalizedExpression(sourceFile: ts.SourceFile, expression: ts.Expression): string {
  return expression.getText(sourceFile).replace(/\s+/g, '')
}

function stripSqlComments(source: string): string {
  let output = ''
  let index = 0
  let lineComment = false
  let blockDepth = 0
  let singleQuote = false
  let doubleQuote = false
  let dollarTag: string | null = null
  while (index < source.length) {
    const current = source[index]
    const next = source[index + 1]
    if (lineComment) {
      if (current === '\n') { lineComment = false; output += '\n' } else output += ' '
      index += 1
      continue
    }
    if (blockDepth > 0) {
      if (current === '/' && next === '*') { blockDepth += 1; output += '  '; index += 2; continue }
      if (current === '*' && next === '/') { blockDepth -= 1; output += '  '; index += 2; continue }
      output += current === '\n' ? '\n' : ' '
      index += 1
      continue
    }
    if (dollarTag) {
      if (source.startsWith(dollarTag, index)) {
        output += dollarTag
        index += dollarTag.length
        dollarTag = null
      } else {
        output += current
        index += 1
      }
      continue
    }
    if (singleQuote) {
      output += current
      if (current === "'" && next === "'") { output += next; index += 2; continue }
      if (current === "'") singleQuote = false
      index += 1
      continue
    }
    if (doubleQuote) {
      output += current
      if (current === '"' && next === '"') { output += next; index += 2; continue }
      if (current === '"') doubleQuote = false
      index += 1
      continue
    }
    if (current === '-' && next === '-') { lineComment = true; output += '  '; index += 2; continue }
    if (current === '/' && next === '*') { blockDepth = 1; output += '  '; index += 2; continue }
    if (current === "'") { singleQuote = true; output += current; index += 1; continue }
    if (current === '"') { doubleQuote = true; output += current; index += 1; continue }
    const tag = source.slice(index).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)?.[0]
    if (tag) { dollarTag = tag; output += tag; index += tag.length; continue }
    output += current
    index += 1
  }
  return output
}

function topLevelSql(source: string): string {
  const sql = stripSqlComments(source)
  let output = ''
  let index = 0
  while (index < sql.length) {
    if (sql[index] === "'") {
      const start = index++
      while (index < sql.length) {
        if (sql[index] === "'" && sql[index + 1] === "'") { index += 2; continue }
        if (sql[index] === "'") { index += 1; break }
        index += 1
      }
      output += ' '.repeat(index - start)
      continue
    }
    const tag = sql.slice(index).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)?.[0]
    if (tag) {
      const start = index
      index += tag.length
      const end = sql.indexOf(tag, index)
      index = end < 0 ? sql.length : end + tag.length
      output += ' '.repeat(index - start)
      continue
    }
    output += sql[index]
    index += 1
  }
  return output
}

function normalizeRole(value: string): string {
  return value.trim().replace(/^"|"$/g, '').toLowerCase()
}

function parseRoleList(value: string): string[] {
  return value.split(',').map(normalizeRole).filter(Boolean)
}

function addRoleEdge(graph: RoleGraph, grantedRole: string, recipient: string): void {
  const recipients = graph.get(grantedRole) ?? new Set<string>()
  recipients.add(recipient)
  graph.set(grantedRole, recipients)
}

function removeRoleEdge(graph: RoleGraph, grantedRole: string, recipient: string): void {
  graph.get(grantedRole)?.delete(recipient)
}

function effectiveRoleMembership(source: string): RoleGraph {
  const graph: RoleGraph = new Map<string, Set<string>>()
  for (const rawStatement of topLevelSql(source).split(';')) {
    const statement = rawStatement.trim()
    if (!statement) continue
    const grant = statement.match(/^grant\s+(.+?)\s+to\s+(.+)$/i)
    if (grant && !/\bon\b/i.test(grant[1]) && !/^(?:all|select|insert|update|delete|truncate|references|trigger|usage|create|connect|temporary|execute)\b/i.test(grant[1].trim())) {
      const grantedRoles = parseRoleList(grant[1])
      const recipients = parseRoleList(grant[2].replace(/\s+with\s+(?:admin|inherit|set)\b[\s\S]*$/i, ''))
      for (const grantedRole of grantedRoles) for (const recipient of recipients) addRoleEdge(graph, grantedRole, recipient)
      continue
    }
    const revoke = statement.match(/^revoke\s+(?:admin\s+option\s+for\s+)?(.+?)\s+from\s+(.+)$/i)
    if (revoke && !/\bon\b/i.test(revoke[1])) {
      const grantedRoles = parseRoleList(revoke[1])
      const recipients = parseRoleList(revoke[2])
      for (const grantedRole of grantedRoles) for (const recipient of recipients) removeRoleEdge(graph, grantedRole, recipient)
    }
  }
  return graph
}

function reachableRoles(graph: RoleGraph, start: string): Set<string> {
  const visited = new Set<string>()
  const queue: string[] = [start]
  while (queue.length > 0) {
    const role = queue.shift() as string
    for (const recipient of graph.get(role) ?? []) {
      if (visited.has(recipient)) continue
      visited.add(recipient)
      queue.push(recipient)
    }
  }
  return visited
}

function browserExposedDefaultPrivilegeStatements(source: string, graph: RoleGraph): string[] {
  const hits: string[] = []
  for (const rawStatement of topLevelSql(source).split(';')) {
    const statement = rawStatement.trim()
    if (!/^alter\s+default\s+privileges\b/i.test(statement)) continue
    const grant = statement.match(/\bgrant\s+(?:execute|all(?:\s+privileges)?)\s+on\s+(?:functions|routines)\s+to\s+(.+)$/i)
    if (!grant) continue
    const schemaClause = statement.match(/\bin\s+schema\s+(.+?)\s+grant\b/i)?.[1]
    if (schemaClause && !parseRoleList(schemaClause).includes('public')) continue
    for (const grantee of parseRoleList(grant[1])) {
      if (grantee === 'public' || grantee === 'anon' || grantee === 'authenticated') { hits.push(statement); break }
      const reachable = reachableRoles(graph, grantee)
      if (reachable.has('anon') || reachable.has('authenticated')) { hits.push(statement); break }
    }
  }
  return hits
}

function splitTopLevelComma(value: string): string[] {
  const values: string[] = []
  let current = ''
  let depth = 0
  for (const character of value) {
    if (character === '(' || character === '[') depth += 1
    if (character === ')' || character === ']') depth -= 1
    if (character === ',' && depth === 0) {
      values.push(current.trim())
      current = ''
    } else {
      current += character
    }
  }
  if (current.trim()) values.push(current.trim())
  return values
}

function normalizeTableTarget(value: string): string {
  return value
    .replace(/^only\s+/i, '')
    .replace(/"/g, '')
    .replace(/\s*\.\s*/g, '.')
    .trim()
    .toLowerCase()
}

function targetListContainsEvidence(value: string): boolean {
  const withoutOptions = value.replace(/\s+(?:restart|continue)\s+identity\b[\s\S]*$/i, '').replace(/\s+(?:cascade|restrict)\s*$/i, '')
  return splitTopLevelComma(withoutOptions).some((target: string) => governedEvidenceTables.has(normalizeTableTarget(target)))
}

function destructiveEvidenceStatements(body: string): string[] {
  const hits: string[] = []
  if (/\bdelete\s+from\s+(?:only\s+)?(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)\b/i.test(body)) hits.push('DELETE')
  if (/\bupdate\s+(?:only\s+)?(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)\b/i.test(body)) hits.push('UPDATE')
  if (/\bmerge\s+into\s+(?:only\s+)?(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)\b[\s\S]*?\bwhen\s+matched\b[\s\S]*?\bthen\s+(?:delete|update)\b/i.test(body)) hits.push('MERGE')
  for (const match of body.matchAll(/\btruncate\s+(?:table\s+)?([\s\S]*?)(?:;|$)/gi)) {
    if (targetListContainsEvidence(match[1])) hits.push('TRUNCATE')
  }
  for (const match of body.matchAll(/\bdrop\s+table\s+(?:if\s+exists\s+)?([\s\S]*?)(?:;|$)/gi)) {
    if (targetListContainsEvidence(match[1])) hits.push('DROP TABLE')
  }
  if (/\balter\s+table\s+(?:only\s+)?(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)\b[\s\S]*?\b(?:drop|rename\s+to|set\s+schema)\b/i.test(body)) hits.push('ALTER TABLE')
  return hits
}

function functionDefinitions(source: string): Map<string, string> {
  const definitions = new Map<string, string>()
  const pattern = /create\s+(?:or\s+replace\s+)?function\s+((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\([^)]*\)([\s\S]*?)(?=\n\s*(?:create\s+(?:or\s+replace\s+)?function|drop\s+(?:function|routine)|alter\s+(?:function|routine))|$)/gi
  for (const match of source.matchAll(pattern)) {
    const name = match[1].replace(/"/g, '').replace(/\s+/g, '').toLowerCase()
    definitions.set(name, match[2] ?? '')
  }
  return definitions
}

function calledKnownFunctions(body: string, knownNames: Set<string>): Set<string> {
  const calls = new Set<string>()
  for (const match of body.matchAll(/\b((?:[A-Za-z_][A-Za-z0-9_]*\.)?[A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
    const candidate = match[1].toLowerCase()
    if (knownNames.has(candidate)) calls.add(candidate)
    else {
      const resolved = [...knownNames].find((known: string) => known.endsWith(`.${candidate}`))
      if (resolved) calls.add(resolved)
    }
  }
  return calls
}

function transitiveDestructiveEvidenceHits(root: string, definitions: Map<string, string>): string[] {
  const hits: string[] = []
  const visited = new Set<string>()
  const visit = (name: string): void => {
    if (visited.has(name)) return
    visited.add(name)
    const body = definitions.get(name)
    if (body === undefined) throw new Error(`Governed routine is missing: ${name}`)
    for (const operation of destructiveEvidenceStatements(body)) hits.push(`${name}:${operation}`)
    for (const called of calledKnownFunctions(body, new Set<string>(definitions.keys()))) visit(called)
  }
  visit(root)
  return hits
}

test('browser security boundary follows the complete local Vite module graph', async () => {
  const modules = await browserModuleGraph()
  expect(modules.length).toBeGreaterThan(0)
  for (const module of modules) {
    expect(module.repositoryPath, `bundled module must stay inside governed src tree: ${module.repositoryPath}`).toMatch(/^src\//)
    expect(executableSensitiveTokens(module.sourceFile), `${module.repositoryPath} must not contain executable service-role material`).toEqual([])
    const constructors = supabaseConstructorImports(module.sourceFile)
    if (module.repositoryPath !== 'src/lib/supabase.ts') {
      expect(constructors.size, `${module.repositoryPath} must not import a Supabase client constructor`).toBe(0)
    }
  }
})

test('central Supabase constructor executable calls derive only from the publishable key', async () => {
  const repositoryPath = 'src/lib/supabase.ts'
  const source = await readText(path.join(repositoryRoot, repositoryPath))
  const sourceFile = parseSource(repositoryPath, source)
  const names = supabaseConstructorImports(sourceFile)
  const calls = constructorCalls(sourceFile, names)
  const initializers = variableInitializers(sourceFile)
  expect(calls.length).toBeGreaterThan(0)
  for (const call of calls) {
    expect(call.arguments.length).toBeGreaterThanOrEqual(2)
    const keyExpression = unwrapFallback(call.arguments[1])
    const resolved = ts.isIdentifier(keyExpression) ? initializers.get(keyExpression.text) : keyExpression
    expect(resolved, 'createClient key argument must resolve to an executable initializer').toBeDefined()
    expect(normalizedExpression(sourceFile, resolved as ts.Expression)).toBe('import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY')
  }
})

test('TypeScript AST preserves regex literals and still sees dynamic Supabase imports', () => {
  const synthetic = String.raw`const load = () => /https:\/\//.test(url) && import('@supabase/supabase-js')`
  const sourceFile = parseSource('synthetic.ts', synthetic)
  expect(moduleSpecifiers(sourceFile)).toContain('@supabase/supabase-js')
})

test('service_role membership cannot reach browser roles transitively', async () => {
  const source = await readMigrationSource()
  const graph = effectiveRoleMembership(source)
  const reachable = reachableRoles(graph, 'service_role')
  expect(reachable.has('anon')).toBe(false)
  expect(reachable.has('authenticated')).toBe(false)
})

test('browser roles cannot inherit wrapper execution through altered default privileges', async () => {
  const source = await readMigrationSource()
  const graph = effectiveRoleMembership(source)
  expect(browserExposedDefaultPrivilegeStatements(source, graph)).toEqual([])
})

test('governed evidence routines reject secondary-target TRUNCATE and destructive table lifecycle DDL transitively', async () => {
  const source = stripSqlComments(await readMigrationSource())
  const definitions = functionDefinitions(source)
  for (const root of [
    'security.platform_capacity_snapshot_internal',
    'public.provider_contact_profiles_claim_service',
    'public.provider_contact_profile_finish_claim_service',
  ]) {
    expect(transitiveDestructiveEvidenceHits(root, definitions), `${root} call graph must remain non-destructive to governed evidence`).toEqual([])
  }
})

test('destructive parser catches governed tables when they are not the first target', () => {
  expect(destructiveEvidenceStatements('TRUNCATE pipeline.scratch, pipeline.evidence_artifacts;')).toContain('TRUNCATE')
  expect(destructiveEvidenceStatements('DROP TABLE pipeline.scratch, storage.objects CASCADE;')).toContain('DROP TABLE')
})
