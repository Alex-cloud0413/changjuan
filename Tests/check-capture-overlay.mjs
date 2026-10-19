import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

// Uses the production detector on in-memory synthetic images. An optional
// authorized fixture is read locally; no frame is copied or published.
const tests = dirname(fileURLToPath(import.meta.url));
const root = resolve(tests, '..');
const args = process.argv.slice(2);
assert.ok(args.length === 0 || (args.length === 2 && args[0] === '--fixture'),
  'Usage: node Tests/check-capture-overlay.mjs [--fixture <authorized-local-frame-directory>]');
mkdirSync(join(root, 'Build'), { recursive: true });
const work = mkdtempSync(join(root, 'Build/overlay-check-'));
const source = readFileSync(join(root, 'LongShotApp/FrameStitcher.swift'), 'utf8');
const first = source.indexOf('enum CaptureOverlayDetector {');
assert.ok(first >= 0, 'Cannot locate production overlay detector');
const production = join(work, 'ProductionCaptureOverlayDetector.swift');
writeFileSync(production, `import Foundation\nimport CoreGraphics\n#if !LONGSHOT_OCR_STUB\nimport Vision\n#endif\n${source.slice(first)}`);

function run(command, argv) {
  const result = spawnSync(command, argv, { encoding: 'utf8', timeout: 120_000, maxBuffer: 4 * 1024 * 1024 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed: ${result.status}`);
  return result.stdout.trim();
}
const swift = run('xcrun', ['--find', 'swiftc']);
const sdk = run('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
const common = ['-O', '-swift-version', '5', '-sdk', sdk, '-module-cache-path', join(work, 'cache'),
  production, join(tests, 'CaptureOverlayDetectorCheck.swift')];
const native = join(work, 'overlay-native');
run(swift, [...common, '-o', native]);
run(native, args);
const fallback = join(work, 'overlay-ocr-fallback');
run(swift, ['-D', 'LONGSHOT_OCR_STUB', ...common, '-o', fallback]);
run(fallback, []);
console.log(`Overlay check artifacts: ${work}`);
