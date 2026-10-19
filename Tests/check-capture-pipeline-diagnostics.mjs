import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

// Synthetic local buffers only. Does not inspect an installed app or user frames.
const tests = dirname(fileURLToPath(import.meta.url));
const root = resolve(tests, '..');
const simulator = process.argv[2];
assert.ok(simulator, 'Pass a booted iOS 27 simulator UDID');
mkdirSync(join(root, 'Build'), { recursive: true });
const work = mkdtempSync(join(root, 'Build/capture-numeric-check-'));
function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} failed`);
  return result.stdout.trim();
}
const source = readFileSync(join(root, 'LongShotApp/ScreenCaptureCoordinator.swift'), 'utf8');
const first = source.indexOf('final class ScreenCaptureHostVisibility:');
const last = source.indexOf('\n#else\n/// ScreenCaptureKit is device-only', first);
assert.ok(first >= 0 && last > first, 'Locate production pipeline and numeric tracker');
const production = join(work, 'ProductionScreenFramePipeline.swift');
writeFileSync(production, 'import CoreImage\nimport CoreMedia\nimport Foundation\nimport ImageIO\nimport UIKit\n' + source.slice(first, last));
const swift = run('xcrun', ['--find', 'swiftc']);
const sdk = run('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-path']);
const binary = join(work, 'capture-numeric-check');
const shared = name => join(root, 'Shared', name);
const app = name => join(root, 'LongShotApp', name);
run(swift, ['-O', '-swift-version', '5', '-target', 'arm64-apple-ios27.0-simulator', '-sdk', sdk,
  '-module-cache-path', join(work, 'cache'), '-D', 'LONGSHOT_CAPTURE_CHECKS', '-D', 'LONGSHOT_SCK_METADATA_STUB',
  shared('CaptureConstants.swift'), shared('CaptureStorage.swift'), shared('OverlapEstimator.swift'), shared('HorizontalTableMatcher.swift'),
  app('FrameStitcher.swift'), app('FramePreparationCache.swift'), production,
  join(tests, 'CapturePipelineDiagnosticsCheck.swift'), '-o', binary]);
run('xcrun', ['simctl', 'spawn', simulator, binary]);
console.log(`Numeric diagnostic test artifacts: ${work}`);
