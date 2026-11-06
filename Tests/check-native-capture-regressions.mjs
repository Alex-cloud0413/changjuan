import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

// Synthetic sample buffers and an isolated temporary capture container only.
// The unavailable simulator SCK key types are replaced with string keys; the
// production attachment parsing, orientation, visibility and JPEG path execute.
const tests = dirname(fileURLToPath(import.meta.url));
const root = resolve(tests, '..');
const simulator = process.argv[2];
assert.ok(simulator, 'Pass a booted iOS 27 simulator UDID');
const work = mkdtempSync(join(tmpdir(), 'LongShotNativeRegressions-'));
function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 180_000, maxBuffer: 8 * 1024 * 1024 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} failed`);
  return result.stdout.trim();
}
const source = readFileSync(join(root, 'LongShotApp/ScreenCaptureCoordinator.swift'), 'utf8');
const first = source.indexOf('final class ScreenCaptureHostVisibility:');
const last = source.indexOf('\n#else\n/// ScreenCaptureKit is device-only', first);
assert.ok(first >= 0 && last > first, 'Locate production native pipeline');
const production = join(work, 'ProductionScreenFramePipeline.swift');
writeFileSync(production, 'import CoreImage\nimport CoreMedia\nimport Foundation\nimport ImageIO\nimport UIKit\n' + source.slice(first, last));
const sdk = run('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-path']);
const binary = join(work, 'native-capture-regressions');
run('xcrun', ['swiftc', '-O', '-swift-version', '5', '-target', 'arm64-apple-ios27.0-simulator', '-sdk', sdk,
  '-module-cache-path', join(work, 'cache'), '-D', 'LONGSHOT_CAPTURE_CHECKS',
  ...['CaptureConstants.swift', 'CaptureStorage.swift', 'OverlapEstimator.swift', 'HorizontalTableMatcher.swift'].map(name => join(root, 'Shared', name)),
  ...['FrameStitcher.swift', 'FramePreparationCache.swift'].map(name => join(root, 'LongShotApp', name)),
  production, join(tests, 'NativeCaptureRegressionsCheck.swift'), '-o', binary]);
run('xcrun', ['simctl', 'spawn', simulator, binary]);
console.log(`Synthetic native capture regression artifacts: ${work}`);
