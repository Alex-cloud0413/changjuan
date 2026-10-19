import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

// Execute the production picker state/continuation methods with an inert picker.
// This never loads ScreenCaptureKit, requests consent, or touches device storage.
const tests = dirname(fileURLToPath(import.meta.url));
const root = resolve(tests, '..');
const source = readFileSync(join(root, 'LongShotApp/ScreenCaptureCoordinator.swift'), 'utf8');
const work = mkdtempSync(join(tmpdir(), 'LongShotPickerLifecycle-'));

function between(start, end) {
  const first = source.indexOf(start);
  const last = source.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `Cannot locate production picker section: ${start}`);
  return source.slice(first, last);
}

const present = between('    func presentPicker() {', '    /// Keep the background LiveActivityIntent');
const waitAndResolve = between('    func waitForPickerResolution()', '    func stopCapture()');
const callbacks = between('    fileprivate func pickerDidCancel(', '    fileprivate func startCapture(');
const deactivate = between('    private func deactivatePicker(', '    private func beginPickerBackgroundTask()');
const harness = `import Foundation

struct SCContentSharingPickerConfiguration {
    var showsMicrophoneControl = true
    var showsCameraControl = true
}

@MainActor
final class InertPicker {
    enum Style { case display }
    var isAvailable = true
    var activeTransitions: [Bool] = []
    var isActive = false { didSet { activeTransitions.append(isActive) } }
    var defaultConfiguration = SCContentSharingPickerConfiguration()
    var observers: [ScreenCapturePickerObserver] = []
    var observerAddCount = 0
    var observerRemoveCount = 0
    var presentCount = 0
    func add(_ observer: ScreenCapturePickerObserver) {
        observers.append(observer)
        observerAddCount += 1
    }
    func remove(_ observer: ScreenCapturePickerObserver) {
        observers.removeAll { $0 === observer }
        observerRemoveCount += 1
    }
    func present(using style: Style) { presentCount += 1 }
}

@MainActor
final class ScreenCapturePickerObserver {
    weak var owner: ScreenCaptureCoordinator?
    let generation: UUID
    init(owner: ScreenCaptureCoordinator, generation: UUID) {
        self.owner = owner
        self.generation = generation
    }
}

@MainActor
final class InertDelegate {
    var willPresentCount = 0
    var errors: [String] = []
    func screenCaptureCoordinatorWillPresentPicker(_ coordinator: ScreenCaptureCoordinator) {
        willPresentCount += 1
    }
    func screenCaptureCoordinator(_ coordinator: ScreenCaptureCoordinator, didFailWith message: String) {
        errors.append(message)
    }
}

@MainActor
final class ScreenCaptureCoordinator {
    let picker: InertPicker
    let delegate: InertDelegate?
    var pickerObserver: ScreenCapturePickerObserver?
    var stream: NSObject?
    var captureGeneration = UUID()
    var isStarting = false
    var isStopping = false
    var awaitingPicker = false
    var pickerWaiters: [CheckedContinuation<Void, Error>] = []
    var pickerFailure: Error?
    var events: [String] = []
    var leaseBeginCount = 0
    var leaseEndCount = 0
    var leaseActive = false
    var abortCount = 0

    init(picker: InertPicker? = nil, delegate: InertDelegate? = nil) {
        self.picker = picker ?? InertPicker()
        self.delegate = delegate ?? InertDelegate()
    }

${present}
${waitAndResolve}
${callbacks}
${deactivate}

    private func recordEvent(_ event: String, detail: String? = nil) { events.append(event) }
    private func beginPickerBackgroundTask() { leaseBeginCount += 1; leaseActive = true }
    private func endPickerBackgroundTask() {
        if leaseActive { leaseEndCount += 1; leaseActive = false }
    }
    private func friendlyMessage(for error: Error) -> String { error.localizedDescription }
    private func abortCapture(message: String, cancelled: Bool = false, stopStream: Bool) async {
        abortCount += 1
        // Inert dependency only. Production callback generation guards and
        // continuation resolution/cleanup above execute without substitution.
        deactivatePicker(error: cancelled ? nil : NSError(domain: "test.abort", code: 4,
            userInfo: [NSLocalizedDescriptionKey: message]))
    }

    func acceptSelectionForTesting() { stream = NSObject(); resolvePicker() }
    func finishForTesting(error: Error? = nil) { stream = nil; deactivatePicker(error: error) }
    func resolveAgainForTesting(error: Error? = nil) { resolvePicker(error: error) }
    func cancelForTesting(generation: UUID) async { await pickerDidCancel(generation: generation) }
    func failForTesting(error: Error, generation: UUID) async {
        await pickerDidFail(with: error, generation: generation)
    }
}
`;
const production = join(work, 'ProductionPickerMethods.swift');
writeFileSync(production, harness);

function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 120_000 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed: ${result.status}`);
  return result.stdout.trim();
}
const swift = run('xcrun', ['--find', 'swiftc']);
const sdk = run('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
const binary = join(work, 'picker-lifecycle-checks');
run(swift, ['-O', '-swift-version', '5', '-sdk', sdk, '-module-cache-path', join(work, 'cache'),
  production, join(tests, 'CapturePickerLifecycleCheck.swift'), '-o', binary]);
run(binary, []);
console.log(`Inert picker artifacts: ${work}`);
