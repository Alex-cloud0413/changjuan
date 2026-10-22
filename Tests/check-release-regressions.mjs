import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { arch, platform, release } from 'node:os';
import { assessPerformance } from './regression-metrics.mjs';

// Local only: no install/launch of the app, signing, network, publication or
// deletion of device data. Native test executables use isolated fixture dirs.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
if (args.length !== 2 || args[0] !== '--simulator') {
  throw new Error('Usage: DEVELOPER_DIR=<Xcode>/Contents/Developer node Tests/check-release-regressions.mjs --simulator <booted iOS 27 UDID>');
}
const simulator = args[1];
const baselineCommit = 'fe9cf807959bf25dc84025b2b7745554d38335c6'; // accepted 1.1.1 (35), not floating HEAD
mkdirSync(join(root, 'Build'), { recursive: true });
const output = mkdtempSync(join(root, 'Build/regression-'));
const report = { schemaVersion: 1, startedAt: new Date().toISOString(), baselineCommit,
  environment: { platform: platform(), arch: arch(), os: release(), developerDir: process.env.DEVELOPER_DIR ?? null, simulator },
  automatedStatus: 'running', releaseReady: false, physicalDeviceStatus: 'not_run', steps: [],
  manualChecklist: 'Tests/Regression-checklist.md' };

function command(command, argv, env = {}) {
  return spawnSync(command, argv, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
    timeout: 600_000, env: { ...process.env, ...env } });
}
function readCommand(commandName, argv) {
  const r = command(commandName, argv);
  if (r.error || r.status !== 0) throw new Error(r.error?.message || r.stderr || `${commandName} failed: ${r.status}`);
  return r.stdout.trim();
}
function fingerprint() {
  const paths = [...new Set(readCommand('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'])
    .split('\0').filter(p => /\.(swift|mjs|pbxproj|plist|strings|json|svg|entitlements)$/.test(p)))].sort();
  const hash = createHash('sha256');
  for (const path of paths) { hash.update(path + '\0'); hash.update(readFileSync(join(root, path))); }
  return hash.digest('hex');
}
function flush() {
  writeFileSync(join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  const rows = report.steps.map(s => `| ${s.id} | ${s.level} | ${s.status} | ${s.seconds.toFixed(2)} | [log](${s.log}) |`);
  const perf = report.performance?.stages?.total;
  writeFileSync(join(output, 'report.md'), `# LongShot regression report\n\n` +
    `Automated: **${report.automatedStatus}**. Physical device: **not run**. Release-ready: **false**.\n\n` +
    `Source SHA-256: \`${report.sourceFingerprint ?? 'unknown'}\`. Baseline: \`${baselineCommit}\`.\n\n` +
    `| Check | Evidence level | Status | Seconds (includes compilation) | Log |\n| --- | --- | --- | --- | --- |\n${rows.join('\n')}\n\n` +
    (perf ? `Algorithm total median ${perf.medianBefore.toFixed(4)} → ${perf.medianAfter.toFixed(4)} s; sample p95 ${perf.p95Before.toFixed(4)} → ${perf.p95After.toFixed(4)} s.\n\n` : '') +
    `Simulator timing is not recording-finish-to-Photos latency. System permission sheets, Control Center, real Dynamic Island, visible notifications and user-page correctness still require the physical-device checklist.\n`);
}
function step(id, level, executable, argv, env = {}) {
  console.log(`RUN ${id}`);
  const started = Date.now();
  const r = command(executable, argv, env);
  const log = `${id}.log`;
  const text = `${r.stdout ?? ''}${r.stderr ?? ''}${r.error ? '\n' + r.error.message : ''}`;
  writeFileSync(join(output, log), text);
  const passed = !r.error && r.status === 0;
  report.steps.push({ id, level, status: passed ? 'passed' : 'failed', seconds: (Date.now() - started) / 1000,
    exitCode: r.status, signal: r.signal, log });
  flush();
  console.log(`${passed ? 'PASS' : 'FAIL'} ${id}`);
  if (!passed) throw new Error(`${id} failed; see ${join(output, log)}`);
  return r.stdout;
}
try {
  report.head = readCommand('git', ['rev-parse', 'HEAD']);
  report.workingTree = readCommand('git', ['status', '--short']);
  report.sourceFingerprint = fingerprint();
  report.environment.xcode = readCommand('xcodebuild', ['-version']);
  const devices = JSON.parse(readCommand('xcrun', ['simctl', 'list', 'devices', 'booted', '--json']));
  const entry = Object.entries(devices.devices).find(([runtime, list]) =>
    /iOS-27-/.test(runtime) && list.some(d => d.udid === simulator && d.state === 'Booted'));
  assert.ok(entry, 'A booted iOS 27 simulator is required; no simulator is started/erased automatically');
  report.environment.runtime = entry[0];
  for (const [name, file] of [['stitcher', 'FrameStitcher.swift'], ['cache', 'FramePreparationCache.swift']]) {
    const source = readCommand('git', ['show', `${baselineCommit}:LongShotApp/${file}`]);
    writeFileSync(join(output, `baseline-${file}`), source);
    report[`${name}BaselineSHA256`] = createHash('sha256').update(source).digest('hex');
  }
  for (const [name, level] of [
    ['regression-metrics', 'report-behavior'], ['home-icon-only', 'source-contract'],
    ['capture-settings', 'source-contract'], ['capture-entry', 'source-contract'],
    ['picker-lifecycle', 'native-with-picker-stubs'], ['capture-overlay', 'native-Vision+OCR-fallback'], ['app-language', 'native+source'],
    ['notification-authorization', 'native-with-system-stubs'], ['storage-cleanup', 'native+source'],
  ]) step(name, level, process.execPath, [`Tests/check-${name}.mjs`]);

  const swift = readCommand('xcrun', ['--find', 'swiftc']);
  const macSDK = readCommand('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
  for (const [id, file] of [['overlap', 'OverlapEstimatorCheck.swift'], ['fine-alignment', 'FineAlignmentPerformanceCheck.swift']]) {
    const binary = join(output, id);
    step(`${id}-compile`, 'build', swift, ['-O', '-swift-version', '5', '-sdk', macSDK,
      'Shared/OverlapEstimator.swift', `Tests/${file}`, '-o', binary]);
    step(id, 'native-algorithm', binary, []);
  }
  step('horizontal-table-matcher', 'native-algorithm', process.execPath,
    ['Tests/check-horizontal-table-matcher.mjs']);
  step('horizontal-frozen-panes', 'native-algorithm+synthetic-pixel-oracle', process.execPath,
    ['Tests/check-horizontal-frozen-panes.mjs', simulator]);
  // Run the focused overlay gate before the longer capture/performance suite.
  step('horizontal-floating-controls', 'native-algorithm+synthetic-visual', process.execPath,
    ['Tests/check-horizontal-floating-controls.mjs', simulator]);
  step('capture-pipeline-diagnostics', 'native-with-SCK-metadata-stubs', process.execPath,
    ['Tests/check-capture-pipeline-diagnostics.mjs', simulator]);
  step('duo-preview', 'native-UIKit+injected-system-insets', process.execPath,
    ['Tests/check-duo-preview.mjs', simulator]);
  const captureLog = step('capture', 'optimized-simulator-behavior', process.execPath,
    ['Tests/check-capture-improvements.mjs', simulator], {
      LONGSHOT_STITCH_BASELINE: join(output, 'baseline-FrameStitcher.swift'),
      LONGSHOT_CACHE_BASELINE: join(output, 'baseline-FramePreparationCache.swift'),
    });
  step('horizontal-spreadsheet', 'native-algorithm', process.execPath,
    ['Tests/check-horizontal-spreadsheet.mjs', simulator]);
  step('horizontal-table-jitter', 'native-algorithm', process.execPath,
    ['Tests/check-horizontal-table-jitter.mjs', simulator]);
  const metricLines = captureLog.split('\n').filter(line => line.startsWith('LONGSHOT_PERF '));
  assert.equal(metricLines.length, 1, 'Missing or duplicate benchmark: never mark an absent benchmark passed');
  report.performanceSamples = JSON.parse(metricLines[0].slice('LONGSHOT_PERF '.length));
  report.performance = assessPerformance(report.performanceSamples);
  flush();
  assert.equal(report.performance.status, 'passed', `Performance regression: ${report.performance.regressions.join(', ')}`);

  const deviceDerived = join(root, 'Build/regression-device');
  const simDerived = join(root, 'Build/regression-simulator');
  const common = ['-project', 'LongShot.xcodeproj', '-scheme', 'LongShot', '-configuration', 'Release'];
  for (const [id, destination, derived] of [
    ['device', 'generic/platform=iOS', deviceDerived], ['simulator', `platform=iOS Simulator,id=${simulator}`, simDerived],
  ]) step(`build-${id}`, 'unsigned-Release-build', 'xcodebuild', [...common, '-destination', destination,
    '-derivedDataPath', derived, 'CODE_SIGNING_ALLOWED=NO', 'build']);
  const deviceApp = join(deviceDerived, 'Build/Products/Release-iphoneos/LongShot.app');
  const simulatorApp = join(simDerived, 'Build/Products/Release-iphonesimulator/LongShot.app');
  step('bundle-resources', 'built-resource', process.execPath, ['Tests/check-language-resources.mjs', deviceApp]);
  const info = path => JSON.parse(readCommand('plutil', ['-convert', 'json', '-o', '-', path]));
  const appInfo = info(join(deviceApp, 'Info.plist'));
  const widgetInfo = info(join(deviceApp, 'PlugIns/LongScrollWidgets.appex/Info.plist'));
  for (const key of ['CFBundleVersion', 'CFBundleShortVersionString', 'MinimumOSVersion']) assert.equal(appInfo[key], widgetInfo[key]);
  const executable = readFileSync(join(deviceApp, appInfo.CFBundleExecutable));
  for (const hook of ['--snapshot-', '--benchmark-latest', '--export-frames']) {
    assert.ok(!executable.includes(Buffer.from(hook)), `Developer hook must not enter standard Release: ${hook}`);
  }
  report.build = { version: appInfo.CFBundleShortVersionString, build: appInfo.CFBundleVersion,
    minimumOS: appInfo.MinimumOSVersion, signed: false, installedOnPhone: false };
  const simSDK = readCommand('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-path']);
  const iconBinary = join(output, 'control-icon');
  step('control-icon-compile', 'build', swift, ['-O', '-parse-as-library', '-sdk', simSDK,
    '-target', 'arm64-apple-ios27.0-simulator', 'Tests/ControlIconVisualCheck.swift', '-o', iconBinary]);
  step('control-icon', 'compiled-symbol-render', 'xcrun', ['simctl', 'spawn', simulator, iconBinary,
    simulatorApp, simulatorApp, output]);
  const widgetBundle = join(simulatorApp, 'PlugIns/LongScrollWidgets.appex');
  const widgetOutput = join(output, 'widget-icons');
  mkdirSync(widgetOutput);
  step('widget-control-icon', 'compiled-symbol-render', 'xcrun', ['simctl', 'spawn', simulator, iconBinary,
    widgetBundle, widgetBundle, widgetOutput]);
  step('diff-whitespace', 'source-hygiene', 'git', ['diff', '--check']);
  assert.equal(fingerprint(), report.sourceFingerprint, 'Source changed during regression; rerun for coherent evidence');
  report.automatedStatus = 'passed';
} catch (error) {
  report.automatedStatus = 'failed';
  report.failure = error.message;
  process.exitCode = 1;
  console.error(error.message);
} finally {
  report.finishedAt = new Date().toISOString();
  flush();
  console.log(`Report: ${join(output, 'report.md')}`);
  console.log('Physical-device acceptance NOT RUN; automated success alone does not authorize release.');
}
