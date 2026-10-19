import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

// Local synthetic images only. Optional old source proves the regression RED.
const simulator = process.argv[2];
if (!simulator) throw new Error('Pass an already booted iOS 27 simulator UDID');
const work = mkdtempSync(join(tmpdir(), 'LongShotFloatingControlCheck-'));
const sdk = execFileSync('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-path'], { encoding: 'utf8' }).trim();
const stitcher = process.env.LONGSHOT_STITCHER_SOURCE ?? 'LongShotApp/FrameStitcher.swift';
const binary = join(work, 'floating-controls');
execFileSync('xcrun', ['swiftc', '-O', '-swift-version', '5', '-D', 'LONGSHOT_CAPTURE_CHECKS',
  '-target', 'arm64-apple-ios27.0-simulator', '-sdk', sdk, '-module-cache-path', join(work, 'cache'),
  'Shared/CaptureConstants.swift', 'Shared/CaptureStorage.swift', 'Shared/OverlapEstimator.swift', 'Shared/HorizontalTableMatcher.swift',
  stitcher, 'LongShotApp/FramePreparationCache.swift', 'Tests/HorizontalFloatingControlsCheck.swift', '-o', binary], { stdio: 'inherit' });
execFileSync('xcrun', ['simctl', 'spawn', simulator, binary, ...process.argv.slice(3)], { stdio: 'inherit', timeout: 180_000,
  env: { ...process.env, SIMCTL_CHILD_LONGSHOT_ALIGNMENT_TRACE: process.env.LONGSHOT_ALIGNMENT_TRACE ?? '0' } });
console.log(`Floating-control synthetic artifacts: ${work}; source: ${stitcher}`);
