import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

// Host-only numerical contract: no simulator, device, or recorded frames.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const work = mkdtempSync(join(tmpdir(), 'LongShotTableMatcherCheck-'));
const binary = join(work, 'horizontal-table-matcher');
execFileSync('xcrun', ['swiftc', '-O', '-swift-version', '5',
  '-module-cache-path', join(work, 'cache'),
  'Shared/OverlapEstimator.swift', 'Shared/HorizontalTableMatcher.swift',
  'Tests/HorizontalTableMatcherCheck.swift', '-o', binary],
  {cwd: root, stdio: 'inherit', timeout: 120_000});
execFileSync(binary, [], {cwd: root, stdio: 'inherit', timeout: 120_000});
