import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const work = mkdtempSync(join(tmpdir(), 'longshot-feedback-mail-'));
function run(command, args) {
  const result = spawnSync(command, args, { stdio: 'inherit', timeout: 60_000 });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} failed`);
}

try {
  const binary = join(work, 'check-mail-draft');
  run('xcrun', ['swiftc', '-O', '-swift-version', '5', '-parse-as-library', '-module-cache-path', join(work, 'cache'),
    join(root, 'LongShotApp/FeedbackMailDraft.swift'), join(root, 'Tests/FeedbackMailDraftCheck.swift'), '-o', binary]);
  run(binary, []);
} finally {
  rmSync(work, { recursive: true, force: true });
}
