import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

// Production storage code, isolated temporary files and dedicated defaults only.
// Never opens an installed App Group, a device container or the Photos library.
const tests = dirname(fileURLToPath(import.meta.url));
const root = resolve(tests, '..');
const work = mkdtempSync(join(tmpdir(), 'LongShotStorageRegression-'));
function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed: ${result.status}`);
  return result.stdout.trim();
}
const swift = run('xcrun', ['--find', 'swiftc']);
const sdk = run('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
const flags = ['-O', '-swift-version', '5', '-sdk', sdk, '-module-cache-path', join(work, 'cache')];
const storage = join(work, 'storage-checks');
run(swift, [...flags, '-D', 'LONGSHOT_CAPTURE_CHECKS', join(root, 'Shared/CaptureConstants.swift'),
  join(root, 'Shared/CaptureStorage.swift'), join(tests, 'SavedCaptureCleanupCheck.swift'), '-o', storage]);
run(storage, []);

const notification = readFileSync(join(root, 'LongShotApp/ResultNotificationManager.swift'), 'utf8');
const first = notification.indexOf('struct SavedResultPresentationState:');
const last = notification.indexOf('private struct NotificationDiagnosticError:', first);
assert.ok(first >= 0 && last > first, 'Locate production presentation persistence');
const production = join(work, 'ProductionPresentationStore.swift');
writeFileSync(production, `import Foundation\n${notification.slice(first, last)}`);
const presentation = join(work, 'presentation-checks');
run(swift, [...flags, production, join(tests, 'SavedResultPresentationCheck.swift'), '-o', presentation]);
run(presentation, []);

// Source-level integration contracts supplement, not replace, native testing.
const model = readFileSync(join(root, 'LongShotApp/AppModel.swift'), 'utf8');
const refresh = model.split('func refreshAndProcessIfNeeded() async {')[1].split('func retryProcessing()')[0];
assert.ok(refresh.indexOf('await waitForStorageMaintenance()') < refresh.indexOf('CaptureStorage.allSessions()'));
assert.ok(refresh.indexOf('if CaptureStorage.hasSavedOutputsToPhotos') < refresh.indexOf('await process('),
  'Missing saved preview must never trigger duplicate processing/Photos save');
const processingSource = model.split('private func process(sessionURL:')[1].split('private func restoreSavedResult')[0];
assert.ok(processingSource.indexOf('try await saveToPhotos') < processingSource.indexOf('try CaptureStorage.markOutputsSavedToPhotos'),
  'Success marker follows completed Photos transaction');
assert.ok(processingSource.indexOf('try CaptureStorage.write(updatedManifest') < processingSource.indexOf('await completeSavedResult('));
const completion = model.split('private func completeSavedResult(')[1].split('private func scheduleStorageMaintenance()')[0];
assert.ok(completion.indexOf('await resultNotificationManager.postSavedResult') < completion.indexOf('scheduleStorageMaintenance()'),
  'Cleanup must not delay output/notification delivery');
assert.ok(model.includes('Task.detached(priority: .utility)'));
assert.ok(model.includes('storageMaintenanceWorker?.cancel()'));
assert.ok(model.includes('.union(resultDeliverySessions)'), 'In-flight notification attachments stay protected');
assert.ok(notification.includes('removeDeliveredNotifications(withIdentifiers: identifiers)'));
assert.ok(notification.includes('removePendingNotificationRequests(withIdentifiers: identifiers)'));
assert.ok(!/PHAssetChangeRequest\.(deleteAssets|delete)/.test(model), 'Cleanup never deletes Photos assets');
const cache = readFileSync(join(root, 'LongShotApp/FramePreparationCache.swift'), 'utf8');
assert.ok(cache.includes('CaptureStorage.withFrameCacheMutation'));
assert.ok(cache.includes('guard !CaptureStorage.hasSavedOutputsToPhotos'));
const project = readFileSync(join(root, 'LongShot.xcodeproj/project.pbxproj'), 'utf8');
assert.equal((project.match(/MARKETING_VERSION = 1\.1\.2;/g) || []).length, 4);
const buildVersions = [...project.matchAll(/CURRENT_PROJECT_VERSION = ([^;]+);/g)].map(match => match[1]);
assert.equal(buildVersions.length, 4, 'App and Widgets must each have Debug/Release build numbers');
assert.equal(new Set(buildVersions).size, 1, 'All four configurations must use the same build number');
assert.ok(/^[1-9]\d*$/.test(buildVersions[0]), 'The shared build number must be a positive integer');
console.log(`Storage integration source contracts passed; artifacts: ${work}`);
