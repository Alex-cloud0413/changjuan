import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

// Execute extracted shipping presentation logic, with only model/state stubs.
// No installed app defaults, captures, Photos, or device containers are opened.
const root = resolve(import.meta.dirname, '..');
const home = readFileSync(join(root, 'LongShotApp/ContentView.swift'), 'utf8');
const activity = readFileSync(join(root, 'LongScrollWidgets/LongScrollLiveActivity.swift'), 'utf8');
const work = mkdtempSync(join(tmpdir(), 'LongShotHomePresentation-'));
function between(source, start, end) {
  const first = source.indexOf(start), last = source.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `Missing production section: ${start}`);
  return source.slice(first, last).replaceAll('private ', '');
}
const thumbnail = between(home, '    private var savedThumbnailDescription:', '    private var paperBackground:');
const activityPresentation = between(activity, '    private func actionHint(', '    private func statusDetail(');
const thumbnailView = between(home, '    private func savedThumbnail(', '    private var savedThumbnailDescription:');
assert.ok(thumbnailView.includes('Text(savedThumbnailDescription)'), 'Visible result retains every qualification');
assert.ok(thumbnailView.includes('.accessibilityLabel(language.text("已保存到照片") + "\\n" + savedThumbnailDescription)'),
  'VoiceOver receives the saved state and the same qualifications as the visible result');
const compact = between(activity, '            } compactLeading:', '            .widgetURL(');
assert.equal((compact.match(/\.accessibilityLabel\(statusTitle\(for: context\.state\)\)/g) ?? []).length, 2,
  'Compact and minimal symbols announce actual state');
assert.equal((compact.match(/\.accessibilityHint\(actionHint\(for: context\.state\)\)/g) ?? []).length, 2,
  'Compact and minimal action discovery follows actual state');
assert.ok(compact.includes('.accessibilityHidden(true)'), 'Decorative leading symbol does not duplicate the state');
const extracted = join(work, 'ProductionPresentation.swift');
writeFileSync(extracted, `import Foundation
struct HomePresentation {
  struct Model { var outputsSeparatedByGeometry: Bool; var omittedOccludedBottomRows: Bool }
  let model: Model; let language: AppLanguage
${thumbnail}
}
enum CaptureSurfacePhase: CaseIterable { case idle, choosing, capturing, paused, processing, saved, failed }
struct LongScrollActivityAttributes {
  struct ContentState { let phase: CaptureSurfacePhase; let language: AppLanguage }
}
struct ActivityPresentation {
${activityPresentation}
}
`);
const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
const binary = join(work, 'presentation-checks');
execFileSync('xcrun', ['swiftc', '-O', '-swift-version', '5', '-sdk', sdk, '-module-cache-path', join(work, 'cache'),
  join(root, 'Shared/AppLanguage.swift'), extracted, join(root, 'Tests/HomePresentationCheck.swift'), '-o', binary], { stdio: 'inherit' });
execFileSync(binary, [], { stdio: 'inherit' });
