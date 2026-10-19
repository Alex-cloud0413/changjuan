import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

// Explicit local fixture only. Never exports device data or publishes outputs.
const [simulator, fixture, width, height] = process.argv.slice(2);
assert.ok(simulator && fixture, 'Usage: node Tests/check-capture-replay.mjs <booted-simulator> <authorized-local-fixture> [width height]');
mkdirSync('Build', { recursive: true });
const output = mkdtempSync(resolve('Build/capture-replay-'));
const sdk = execFileSync('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-path'], { encoding: 'utf8' }).trim();
const binary = join(output, 'replay');
execFileSync('xcrun', ['swiftc', '-O', '-swift-version', '5', '-D', 'LONGSHOT_CAPTURE_CHECKS',
  '-target', 'arm64-apple-ios27.0-simulator', '-sdk', sdk, '-module-cache-path', join(output, 'cache'),
  'Shared/CaptureConstants.swift', 'Shared/CaptureStorage.swift', 'Shared/OverlapEstimator.swift', 'Shared/HorizontalTableMatcher.swift',
  'LongShotApp/FrameStitcher.swift', 'LongShotApp/FramePreparationCache.swift',
  'Tests/CaptureReplayCheck.swift', '-o', binary], { stdio: 'inherit' });
execFileSync('xcrun', ['simctl', 'spawn', simulator, binary, resolve(fixture), output,
  ...(width && height ? ['--expect-size', width, height] : [])], { stdio: 'inherit', timeout: 180_000 });
console.log(`Local replay artifacts: ${output}`);
