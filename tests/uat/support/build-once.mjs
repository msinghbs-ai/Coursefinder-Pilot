// Guards: G4 (Platform Admin 26 Oct 2026) test turnaround: identical inputs are built once per worker, not once per spec.
// Several source contracts check that `npm run build` still succeeds. The source tree does not change during a run, so the
// first call in a worker runs the build and later calls in the same worker return its output. A failed build throws every
// time it is asked for, so each calling test still fails on its own.
import { execFileSync } from 'node:child_process'

let result

export function buildOnce() {
  if (!result) {
    try {
      result = { output: execFileSync('npm', ['run', 'build'], { cwd: process.cwd(), env: process.env, encoding: 'utf8', timeout: 60000, stdio: ['ignore', 'pipe', 'pipe'] }) } // fixed: build time-out, unchanged from the specs that called it
    } catch (error) {
      result = { error }
    }
  }
  if (result.error) throw result.error
  return result.output
}
