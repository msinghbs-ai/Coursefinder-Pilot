#!/usr/bin/env python3
"""Guards: Admin #382, verify the existing controller reservation before a write.

Read-only adapter for the canonical Admin coordination ref. It never acquires,
renews, transfers or clears ownership, and never grants release approval.
Public Git/ref and immutable raw-file reads require no extra credential.
"""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest
import urllib.request

ADMIN = 'msinghbs-ai/coursefinder-admin'
PILOT = 'msinghbs-ai/Coursefinder-Pilot'
COORDINATION_REF = 'refs/heads/studysearch-controller'
ALLOWED_KINDS = {
    'deploy-on-merge': {'release'},
    'db-apply-migration': {'release', 'migration'},
    'deploy-edge-functions': {'release'},
    'deployed-uat': {'release', 'validation'},
    'deployed-weekly': {'release', 'validation'},
    'cloudflare-frontend': {'release'},
    'governed-sql': {'write', 'migration'},
    'component-register': {'write'},
    'archive-export': {'write'},
}


def utc(value):
    if not isinstance(value, str) or not value.endswith('Z'):
        raise ValueError('UTC timestamp with Z required')
    return datetime.fromisoformat(value[:-1] + '+00:00')


def git(*args):
    result = subprocess.run(['git', *args], text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise ValueError('Git verification failed; no production action permitted')
    return result.stdout.strip()


def checked_out_tree(commit=None):
    """Check real tracked bytes as well as HEAD, including a recovery checkout."""
    target = git('rev-parse', commit or 'HEAD')
    actual_head = git('rev-parse', 'HEAD')
    if target != actual_head or not re.fullmatch('[a-f0-9]{40}', target):
        raise ValueError('the guarded commit must be the actual checked-out HEAD')
    if git('status', '--porcelain', '--untracked-files=no'):
        raise ValueError('tracked source differs from the reserved commit; restore or revalidate it')
    if git('ls-files', '--others', '--exclude-standard', '--',
           'supabase/migrations', 'supabase/functions', 'supabase/archive', 'scripts/ci'):
        raise ValueError('untracked executable source is outside the reserved Git tree; remove or revalidate it')
    return target, git('rev-parse', target + '^{tree}')


def require_resource_source(entry_point, resource):
    """Bind file-based mutation resources to blobs in the checked-out commit."""
    if entry_point not in ('deploy-on-merge', 'db-apply-migration', 'deploy-edge-functions',
                           'component-register', 'archive-export'):
        return
    require_text(resource, 'mutation resource')
    if (entry_point == 'db-apply-migration' and not resource.startswith('migration:')) or (
            entry_point == 'deploy-edge-functions' and not resource.startswith(('edge_function:', 'retired_function:'))):
        raise ValueError('invalid file-based mutation resource for this entry point')
    if entry_point == 'component-register':
        if resource != 'component_register:ingest-sync':
            raise ValueError('invalid component register mutation resource')
        path = 'scripts/component-register-collect.mjs'
    elif entry_point == 'archive-export':
        if not re.fullmatch(r'archive_definition:[a-z0-9-]+\.json', resource):
            raise ValueError('invalid archive export mutation resource')
        path = 'supabase/archive/' + resource.removeprefix('archive_definition:')
    elif re.fullmatch(r'migration:[0-9]{14}_[a-z0-9_]+\.sql', resource):
        path = 'supabase/migrations/' + resource.removeprefix('migration:')
    elif re.fullmatch(r'edge_function:[a-z0-9-]+', resource):
        path = 'supabase/functions/' + resource.removeprefix('edge_function:') + '/index.ts'
    elif entry_point == 'deploy-edge-functions' and re.fullmatch(r'retired_function:[a-z0-9-]+', resource):
        # Deletion targets are absent by design; the workflow's retired list,
        # missing-source check and separate destructive approval still apply.
        return
    else:
        raise ValueError('invalid file-based mutation resource')
    try:
        if git('cat-file', '-t', 'HEAD:' + path) != 'blob':
            raise ValueError('not a blob')
    except ValueError:
        raise ValueError('selected mutation source is not tracked at HEAD')


def read_live_state():
    def head():
        result = git('ls-remote', 'https://github.com/' + ADMIN + '.git', COORDINATION_REF)
        lines = [line.split() for line in result.splitlines()]
        if len(lines) != 1 or len(lines[0]) != 2 or lines[0][1] != COORDINATION_REF:
            raise ValueError('canonical controller ref is absent or ambiguous')
        value = lines[0][0]
        if not re.fullmatch('[a-f0-9]{40}', value):
            raise ValueError('controller ref did not resolve to an immutable commit')
        return value

    before = head()
    url = 'https://raw.githubusercontent.com/' + ADMIN + '/' + before + '/controller.json'
    request = urllib.request.Request(url, headers={'User-Agent': 'StudySearch-controller-guard', 'Cache-Control': 'no-cache'})
    with urllib.request.urlopen(request, timeout=20) as response:
        state = json.load(response)
    if head() != before:
        raise ValueError('controller ref changed during verification; reconcile before retry')
    return before, state


def require_text(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(label + ' is required')


def validate(state, execution, generation, operation, entry_point, target_tree, reserved_trees,
             resource=None, sql_digest=None, now=None):
    """Pure gate; tree identities come from actual Git objects, never caller JSON."""
    now = now or datetime.now(timezone.utc)
    for value, label in [(execution, 'controller execution'), (operation, 'operation id')]:
        require_text(value, label)
    if entry_point not in ALLOWED_KINDS:
        raise ValueError('unknown production entry point')
    if state.get('schema_version') != '1.0.0' or state.get('coordination_id') != 'studysearch-integration-controller':
        raise ValueError('unsupported canonical ownership record')
    owner, op = state.get('owner') or {}, state.get('in_flight') or {}
    if state.get('status') != 'active' or owner.get('execution_id') != execution:
        raise ValueError('exclusive ownership is inactive or belongs to another execution')
    if not isinstance(generation, int) or isinstance(generation, bool) or generation < 1 or state.get('generation') != generation:
        raise ValueError('controller generation is stale or absent')
    if utc(state.get('lease_expires_at')) <= now:
        raise ValueError('ownership lease expired; in-flight reservation remains held')
    if utc(state.get('heartbeat_at')) > now or utc(state.get('updated_at')) > now:
        raise ValueError('future ownership evidence is invalid')
    if state.get('adoption', {}).get('status') != 'verified' or state.get('reconciliation', {}).get('status') != 'verified':
        raise ValueError('entry-point adoption/live reconciliation is unverified')
    if state.get('transfer', {}).get('status') != 'completed':
        raise ValueError('successor transfer is not completed')
    if op.get('id') != operation or op.get('execution_id') != execution or op.get('generation') != generation:
        raise ValueError('matching persistent operation reservation is required')
    if op.get('kind') not in ALLOWED_KINDS[entry_point]:
        raise ValueError('operation kind does not authorise this entry point')
    for key in ('approval_ref', 'checkpoint_ref'):
        if not isinstance(op.get(key), str) or not op[key].startswith('https://github.com/' + ADMIN + '/'):
            raise ValueError('durable Admin ' + key + ' is required')
    refs = op.get('evidence_refs')
    if not isinstance(refs, list) or not refs or not all(isinstance(ref, str) for ref in refs):
        raise ValueError('operation evidence references are malformed')
    if 'entry_point:' + entry_point not in refs:
        raise ValueError('operation is not reserved for this entry point')
    commits = [ref.removeprefix('pilot_commit:') for ref in refs if ref.startswith('pilot_commit:')]
    if len(commits) != 1 or not re.fullmatch('[a-f0-9]{40}', commits[0]):
        raise ValueError('one exact tested Pilot commit must be reserved')
    if reserved_trees.get(commits[0]) != target_tree or not re.fullmatch('[a-f0-9]{40}', target_tree or ''):
        raise ValueError('target Git tree differs from the reserved/tested code')
    if entry_point in ('component-register', 'archive-export'):
        require_text(resource, 'mutation resource')
    if resource and resource not in refs:
        raise ValueError('resource is outside this operation reservation')
    if resource and resource.startswith('retired_function:') and not any(
            ref.startswith('destructive_approval_ref:https://github.com/' + ADMIN + '/') for ref in refs):
        raise ValueError('retired-function deletion requires its separate destructive approval record')
    if entry_point == 'governed-sql' and (not sql_digest or 'sql_sha256:' + sql_digest not in refs):
        raise ValueError('governed SQL bytes are not reserved by digest')
    return commits[0]


def context(args):
    message = git('show', '-s', '--format=%B', 'HEAD')
    fields = [('execution_id', 'CONTROLLER_EXECUTION_ID', 'Controller-Execution'),
              ('generation', 'CONTROLLER_GENERATION', 'Controller-Generation'),
              ('operation_id', 'CONTROLLER_OPERATION_ID', 'Controller-Operation')]
    values = {}
    for attr, env, trailer in fields:
        value = getattr(args, attr) or os.environ.get(env)
        if not value:
            matches = re.findall(r'(?m)^' + trailer + r':[ \t]*([^\n]+)$', message)
            if len(matches) != 1:
                raise ValueError('one ' + trailer + ' trailer or explicit context is required')
            value = matches[0].strip()
        require_text(str(value), trailer)
        values[attr] = value
    try:
        values['generation'] = int(values['generation'])
    except (TypeError, ValueError):
        raise ValueError('controller generation must be an integer')
    return values


def self_test():
    class GateTests(unittest.TestCase):
        def setUp(self):
            self.now = datetime(2026, 11, 6, 12, tzinfo=timezone.utc)
            self.commit, self.tree = 'a' * 40, 'b' * 40
            self.state = {'schema_version': '1.0.0', 'coordination_id': 'studysearch-integration-controller',
                'status': 'active', 'owner': {'execution_id': 'test-execution'}, 'generation': 2,
                'lease_expires_at': '2026-11-06T13:00:00Z', 'heartbeat_at': '2026-11-06T11:50:00Z',
                'updated_at': '2026-11-06T11:50:00Z', 'adoption': {'status': 'verified'},
                'reconciliation': {'status': 'verified'}, 'transfer': {'status': 'completed'},
                'in_flight': {'id': 'release-one', 'execution_id': 'test-execution', 'generation': 2,
                    'kind': 'release', 'approval_ref': 'https://github.com/' + ADMIN + '/issues/382',
                    'checkpoint_ref': 'https://github.com/' + ADMIN + '/commit/' + 'c' * 40,
                    'evidence_refs': ['entry_point:deploy-on-merge', 'pilot_commit:' + self.commit,
                                      'migration:20261106500000_feature.sql']}}
        def check(self, **kwargs):
            return validate(self.state, 'test-execution', 2, 'release-one', 'deploy-on-merge',
                            self.tree, {self.commit: self.tree}, now=self.now, **kwargs)
        def test_matching_reservation_allows_same_tested_tree(self):
            self.assertEqual(self.check(resource='migration:20261106500000_feature.sql'), self.commit)
            for entry, resource in [('component-register', 'component_register:ingest-sync'),
                                    ('archive-export', 'archive_definition:approved-export.json')]:
                self.state['in_flight'].update(kind='write', evidence_refs=[
                    'entry_point:' + entry, 'pilot_commit:' + self.commit, resource])
                self.assertEqual(validate(self.state, 'test-execution', 2, 'release-one', entry,
                    self.tree, {self.commit:self.tree}, resource=resource, now=self.now), self.commit)
                for wrong in (None, 'unreserved:resource'):
                    with self.assertRaises(ValueError):
                        validate(self.state, 'test-execution', 2, 'release-one', entry,
                            self.tree, {self.commit:self.tree}, resource=wrong, now=self.now)
        def test_each_authority_failure_refuses(self):
            for key, value in [('status', 'reconciliation'), ('generation', 1), ('owner', None),
                ('lease_expires_at', '2026-11-06T12:00:00Z'), ('heartbeat_at', '2026-11-06T14:00:00Z'),
                ('adoption', {'status':'pending'}), ('transfer', {'status':'published'}), ('in_flight', None)]:
                with self.subTest(key=key):
                    original = copy.deepcopy(self.state)
                    self.state[key] = value
                    with self.assertRaises((ValueError, TypeError)):
                        self.check()
                    self.state = original
            # The operational SQL/Storage writers use the identical authority gate.
            for entry, resource in [('component-register', 'component_register:ingest-sync'),
                                    ('archive-export', 'archive_definition:approved-export.json')]:
                self.state['in_flight'].update(kind='write', evidence_refs=[
                    'entry_point:' + entry, 'pilot_commit:' + self.commit, resource])
                for key, value in [('status', 'released'), ('owner', None), ('generation', 1),
                        ('lease_expires_at', '2026-11-06T12:00:00Z'), ('adoption', {'status':'pending'})]:
                    original = copy.deepcopy(self.state)
                    self.state[key] = value
                    with self.subTest(entry=entry, key=key), self.assertRaises((ValueError, TypeError)):
                        validate(self.state, 'test-execution', 2, 'release-one', entry,
                            self.tree, {self.commit:self.tree}, resource=resource, now=self.now)
                    self.state = original
        def test_code_resource_and_operation_cannot_be_repurposed(self):
            with self.assertRaises(ValueError): self.check(resource='edge_function:unreserved')
            with self.assertRaises(ValueError):
                validate(self.state, 'test-execution', 2, 'release-one', 'deploy-on-merge',
                         'd' * 40, {self.commit: self.tree}, now=self.now)
            self.state['in_flight']['evidence_refs'].append('pilot_commit:' + 'e' * 40)
            with self.assertRaises(ValueError): self.check()
        def test_reserved_sql_digest_is_required(self):
            op = self.state['in_flight']; op['kind'] = 'write'
            op['evidence_refs'].append('entry_point:governed-sql')
            with self.assertRaises(ValueError):
                validate(self.state, 'test-execution', 2, 'release-one', 'governed-sql',
                         self.tree, {self.commit:self.tree}, now=self.now, sql_digest='0'*64)
            op['evidence_refs'].append('sql_sha256:' + '0'*64)
            validate(self.state, 'test-execution', 2, 'release-one', 'governed-sql', self.tree,
                     {self.commit:self.tree}, now=self.now, sql_digest='0'*64)
        def test_retired_function_does_not_inherit_generic_release_approval(self):
            refs = self.state['in_flight']['evidence_refs']
            refs.extend(['entry_point:deploy-edge-functions', 'retired_function:retired-probe'])
            with self.assertRaisesRegex(ValueError, 'separate destructive approval'):
                validate(self.state, 'test-execution', 2, 'release-one', 'deploy-edge-functions', self.tree,
                         {self.commit:self.tree}, resource='retired_function:retired-probe', now=self.now)
            refs.append('destructive_approval_ref:https://github.com/' + ADMIN + '/issues/382')
            validate(self.state, 'test-execution', 2, 'release-one', 'deploy-edge-functions', self.tree,
                     {self.commit:self.tree}, resource='retired_function:retired-probe', now=self.now)
        def test_protected_verifier_checks_a_pre_guard_recovery_checkout_and_rejects_drift(self):
            import importlib.util
            import shutil
            import tempfile
            original_cwd = os.getcwd()
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                candidate = root / 'candidate'
                candidate.mkdir()
                # Equivalent to staging from github.workflow_sha into RUNNER_TEMP
                # before actions/checkout selects the authorised older candidate.
                staged = root / 'studysearch-controller-guard.py'
                shutil.copyfile(Path(__file__).resolve(), staged)
                os.chdir(candidate)
                try:
                    git('init', '--quiet')
                    git('config', 'user.name', 'Controller gate test')
                    git('config', 'user.email', 'controller-gate@example.invalid')
                    source = candidate / 'supabase/migrations/20261106500000_feature.sql'
                    source.parent.mkdir(parents=True)
                    source.write_text('select 1;\n')
                    function = candidate / 'supabase/functions/test-reader/index.ts'
                    function.parent.mkdir(parents=True)
                    function.write_text('export default () => null;\n')
                    definition = candidate / 'supabase/archive/approved-export.json'
                    definition.parent.mkdir(parents=True)
                    definition.write_text('{"bucket":"approved-archive","prefix":"fixture","sets":[]}\n')
                    collector = candidate / 'scripts/component-register-collect.mjs'
                    collector.parent.mkdir(parents=True)
                    collector.write_text('export default () => null;\n')
                    (candidate / '.gitignore').write_text('node_modules/\ndist/\nuat-artifacts/\n')
                    git('add', '.')
                    git('commit', '--quiet', '-m', 'Recovery candidate predating the guard')
                    self.assertFalse((candidate / 'scripts/ci/controller-guard.py').exists())
                    spec = importlib.util.spec_from_file_location('staged_controller_gate', staged)
                    protected = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(protected)
                    commit, tree = protected.checked_out_tree()
                    self.state['in_flight']['evidence_refs'] = ['entry_point:db-apply-migration',
                        'pilot_commit:' + commit, 'migration:20261106500000_feature.sql']
                    protected.validate(self.state, 'test-execution', 2, 'release-one',
                        'db-apply-migration', tree, {commit:tree},
                        resource='migration:20261106500000_feature.sql', now=self.now)
                    protected.require_resource_source('db-apply-migration', 'migration:20261106500000_feature.sql')
                    protected.require_resource_source('deploy-edge-functions', 'edge_function:test-reader')
                    protected.require_resource_source('component-register', 'component_register:ingest-sync')
                    protected.require_resource_source('archive-export', 'archive_definition:approved-export.json')
                    with self.assertRaisesRegex(ValueError, 'not tracked at HEAD'):
                        protected.require_resource_source('archive-export', 'archive_definition:not-tracked.json')
                    with self.assertRaisesRegex(ValueError, 'invalid archive export'):
                        protected.require_resource_source('archive-export', 'archive_definition:../escape.json')
                    with self.assertRaisesRegex(ValueError, 'invalid component register'):
                        protected.require_resource_source('component-register', 'component_register:other')
                    with self.assertRaisesRegex(ValueError, 'invalid file-based mutation resource'):
                        protected.require_resource_source('db-apply-migration', 'edge_function:test-reader')
                    with self.assertRaisesRegex(ValueError, 'not tracked at HEAD'):
                        protected.require_resource_source('deploy-edge-functions', 'edge_function:not-tracked')
                    source.write_text('select 2;\n')
                    with self.assertRaisesRegex(ValueError, 'tracked source differs'):
                        protected.checked_out_tree()
                    source.write_text('select 1;\n')
                    for relative in ('supabase/migrations/20261106500001_untracked.sql',
                                     'supabase/functions/untracked/index.ts', 'scripts/ci/untracked.py',
                                     'supabase/archive/untracked.json'):
                        extra = candidate / relative
                        extra.parent.mkdir(parents=True, exist_ok=True)
                        extra.write_text('unreserved executable source\n')
                        with self.assertRaisesRegex(ValueError, 'untracked executable source'):
                            protected.checked_out_tree()
                        extra.unlink()
                    for relative in ('node_modules/package/index.js', 'dist/assets/index.js',
                                     'uat-artifacts/generated/results.json'):
                        output = candidate / relative
                        output.parent.mkdir(parents=True, exist_ok=True)
                        output.write_text('generated output\n')
                    # Restore/clean succeeds; dependencies and reports remain allowed.
                    self.assertEqual(protected.checked_out_tree(), (commit, tree))
                    # A separately governed SQL file may be outside the source
                    # tree: its exact bytes are bound by the existing digest gate.
                    sql_file = root / 'approved-recovery.sql'
                    sql_file.write_text('select 3;\n')
                    digest = hashlib.sha256(sql_file.read_bytes()).hexdigest()
                    self.state['in_flight'].update(kind='write', evidence_refs=[
                        'entry_point:governed-sql', 'pilot_commit:' + commit, 'sql_sha256:' + digest])
                    protected.require_resource_source('governed-sql', None)
                    protected.validate(self.state, 'test-execution', 2, 'release-one',
                        'governed-sql', tree, {commit:tree}, sql_digest=digest, now=self.now)
                finally:
                    os.chdir(original_cwd)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(GateTests))
    return 0 if result.wasSuccessful() else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--entry-point', choices=ALLOWED_KINDS)
    parser.add_argument('--execution-id')
    parser.add_argument('--generation')
    parser.add_argument('--operation-id')
    parser.add_argument('--commit')
    parser.add_argument('--resource')
    parser.add_argument('--sql-file')
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.entry_point:
        parser.error('--entry-point is required')
    values = context(args)
    head, state = read_live_state()
    target, target_tree = checked_out_tree(args.commit)
    require_resource_source(args.entry_point, args.resource)
    refs = (state.get('in_flight') or {}).get('evidence_refs') or []
    reserved_trees = {}
    for ref in refs:
        if isinstance(ref, str) and re.fullmatch('pilot_commit:[a-f0-9]{40}', ref):
            commit = ref.removeprefix('pilot_commit:')
            # No implicit fetch/replay: the release must check out the tested
            # source with enough history to verify its immutable tree object.
            reserved_trees[commit] = git('rev-parse', commit + '^{tree}')
    digest = hashlib.sha256(Path(args.sql_file).read_bytes()).hexdigest() if args.sql_file else None
    approved = validate(state, values['execution_id'], values['generation'], values['operation_id'],
                        args.entry_point, target_tree, reserved_trees,
                        resource=args.resource, sql_digest=digest)
    print(json.dumps({'controller_head': head, 'generation': values['generation'],
        'execution_id': values['execution_id'], 'operation_id': values['operation_id'],
        'entry_point': args.entry_point, 'target_commit': target, 'tested_commit': approved,
        'resource': args.resource,
        'verifier_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'verified_at': datetime.now(timezone.utc).isoformat().replace('+00:00','Z')}))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        print('BLOCKED: controller authority could not be verified: ' + str(error), file=sys.stderr)
        sys.exit(1)
