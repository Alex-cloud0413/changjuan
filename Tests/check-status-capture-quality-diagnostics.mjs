import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

// macOS native ImageIO/CoreGraphics checks, synthetic pixels only. No device,
// Photos access, user images, output retouching, or installed app state.
const tests = dirname(fileURLToPath(import.meta.url));
const root = resolve(process.argv[2] ?? resolve(tests, '..'));
const work = mkdtempSync(join(tmpdir(), 'longshot-status-quality-check-'));
function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 120_000, maxBuffer: 4 * 1024 * 1024 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} failed`);
}
const source = readFileSync(join(root, 'LongShotApp/CaptureProcessingDiagnostics.swift'), 'utf8');
const first = source.indexOf('#if LONGSHOT_STATUS_QUALITY_DIAGNOSTICS');
assert.ok(first >= 0, 'Locate private-build status quality helper');
const production = join(work, 'ProductionStatusCaptureQualityDiagnostics.swift');
writeFileSync(production, source.slice(first));
const binary = join(work, 'status-quality-check');
run('xcrun', ['swiftc', '-O', '-swift-version', '5', '-module-cache-path', join(work, 'cache'),
  '-D', 'LONGSHOT_STATUS_QUALITY_DIAGNOSTICS', '-D', 'LONGSHOT_CAPTURE_CHECKS', '-parse-as-library',
  production, join(tests, 'StatusCaptureQualityDiagnosticsCheck.swift'), '-o', binary]);
run(binary, [join(work, 'artifacts')]);
console.log(`Synthetic status diagnostic artifacts: ${work}`);
