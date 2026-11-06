import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

// Private images are passed to a read-only native check. Only synthetic fixtures
// and extracted production source are written to this isolated temporary root.
const tests = dirname(fileURLToPath(import.meta.url));
const project = resolve(tests, '..');
const args = process.argv.slice(2);
let fixture;
let simulator;
for (let index = 0; index < args.length; index += 2) {
  const value = args[index + 1];
  assert.ok(value, `Missing value for ${args[index]}`);
  if (args[index] === '--fixture') fixture = resolve(value);
  else if (args[index] === '--simulator') simulator = value;
  else throw new Error('Usage: node Tests/check-statusbar-crop.mjs [--fixture <private-local-image>] [--simulator <booted-UDID>]');
}
const work = mkdtempSync(join(tmpdir(), 'LongShotStatusBarChecks-'));
function run(command, argv) {
  const result = spawnSync(command, argv, { encoding: 'utf8', timeout: 180_000, maxBuffer: 8 * 1024 * 1024 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed: ${result.status}`);
  return result.stdout.trim();
}
const source = readFileSync(join(project, 'LongShotApp/FrameStitcher.swift'), 'utf8');
const first = source.indexOf('enum CaptureStatusBarDetector {');
const last = source.indexOf('enum CaptureOverlayDetector {', first);
assert.ok(first >= 0 && last > first, 'Status detector must precede the existing overlay detector');
const extracted = join(work, 'ProductionCaptureStatusBarDetector.swift');
writeFileSync(extracted, `import CoreGraphics\nimport Foundation\nimport Vision\n${source.slice(first, last)}`);
const swift = run('xcrun', ['--find', 'swiftc']);
const hostSDK = run('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
const native = join(work, 'statusbar-native');
run(swift, ['-O', '-swift-version', '5', '-sdk', hostSDK, '-module-cache-path', join(work, 'host-cache'),
  extracted, join(tests, 'StatusBarCropCheck.swift'), '-o', native]);
run(native, fixture ? ['--fixture', fixture] : []);

if (simulator) {
  const sdk = run('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-path']);
  const binary = join(work, 'statusbar-integration');
  const shared = name => join(project, 'Shared', name);
  const app = name => join(project, 'LongShotApp', name);
  run(swift, ['-O', '-swift-version', '5', '-target', 'arm64-apple-ios27.0-simulator', '-sdk', sdk,
    '-module-cache-path', join(work, 'simulator-cache'), '-D', 'LONGSHOT_CAPTURE_CHECKS',
    shared('CaptureConstants.swift'), shared('CaptureStorage.swift'), shared('OverlapEstimator.swift'),
    shared('HorizontalTableMatcher.swift'), app('FrameStitcher.swift'), app('FramePreparationCache.swift'),
    join(tests, 'StatusBarCropCheck.swift'), '-o', binary]);
  run('xcrun', ['simctl', 'spawn', simulator, binary, '--integration']);
}
console.log(`Status-bar check artifacts (synthetic/extracted source only): ${work}`);
