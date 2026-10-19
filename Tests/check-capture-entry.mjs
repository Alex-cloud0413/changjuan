import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const intents = read('Shared/CaptureSystemIntegration.swift');
for (const name of ['ToggleLongScrollIntent', 'FinishLongScrollIntent']) {
  const section = intents.split(`struct ${name}: LiveActivityIntent {`)[1]?.split('func perform()')[0];
  assert.ok(section, `Missing ${name}`);
  const current = section.split('#if LONGSHOT_SCREEN_CAPTURE_KIT')[1]?.split('#else')[0];
  assert.ok(current?.includes('static let openAppWhenRun = false'));
  assert.ok(current?.includes('static var supportedModes: IntentModes { .background }'));
}
assert.ok(intents.includes('performSystemCaptureAction(finishOnly: true)'));
assert.ok(intents.includes('performSystemCaptureAction(finishOnly: false)'));
const coordinator = read('LongShotApp/ScreenCaptureCoordinator.swift');
assert.ok(coordinator.includes('picker.present(using: .display)'));
assert.ok(coordinator.includes('func waitForPickerResolution() async throws'));
assert.ok(coordinator.includes('withCheckedThrowingContinuation { pickerWaiters.append($0) }'));
assert.ok(coordinator.includes('configuration.capturesAudio = false'));
assert.ok(coordinator.includes('configuration.showsMicrophoneControl = false'));
assert.ok(coordinator.includes('configuration.showsCameraControl = false'));
const controls = read('LongScrollWidgets/LongScrollCaptureControl.swift');
assert.equal((controls.match(/Image\(\.longJuanCaptureV3\)/g) || []).length, 2);
assert.ok(controls.includes('ControlWidgetButton(action: NextLongScrollPageIntent())'));
assert.ok(controls.includes('.disabled(phase != .capturing && phase != .paused)'));
const activity = read('LongScrollWidgets/LongScrollLiveActivity.swift');
assert.ok(activity.includes('等面板收起再滚动 · 长按灵动岛接页'));
assert.ok(activity.includes('Button(intent: NextLongScrollPageIntent())'));
assert.ok(activity.includes('Button(intent: FinishLongScrollIntent())'));
console.log('Capture entry source contracts passed: background intents, consent lifetime, no audio, persistent page control, island prompt/actions. Not a device end-to-end test.');
