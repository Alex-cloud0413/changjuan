import assert from 'node:assert/strict';
import { copyFileSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

// Run after the ordinary regressions on a test simulator with Mail unconfigured.
// This installs the supplied simulator app and replaces its clipboard with synthetic text.
// The chooser check cancels once, then selects Default Mail App with synthetic text. It never sends a message.
const [simulatorFlag, simulator, appFlag, appPath, ...remaining] = process.argv.slice(2);
assert.ok(simulatorFlag === '--simulator' && /^[0-9A-F-]{36}$/i.test(simulator ?? '')
  && appFlag === '--app' && appPath && remaining.length === 0,
'Usage: node Tests/check-feedback-ui.mjs --simulator <booted iOS 27 UDID> --app <built LongShot.app>');
const app = resolve(appPath);
const info = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', join(app, 'Info.plist')], { encoding: 'utf8' }));
assert.equal(info.CFBundleIdentifier, 'com.gaoyiming.longshot.private');
assert.ok(info.CFBundleSupportedPlatforms.includes('iPhoneSimulator'), 'Pass a simulator app bundle');
const devices = JSON.parse(execFileSync('xcrun', ['simctl', 'list', 'devices', 'booted', '--json'], { encoding: 'utf8' })).devices;
assert.ok(Object.entries(devices).some(([runtime, entries]) => /iOS-27-/.test(runtime)
  && entries.some(device => device.udid.toUpperCase() === simulator.toUpperCase() && device.state === 'Booted')),
'A booted iOS 27 simulator is required');

const work = mkdtempSync(join(tmpdir(), 'LongShotFeedbackUI-'));
copyFileSync(join(import.meta.dirname, 'FeedbackUICheck.swift'), join(work, 'FeedbackUICheck.swift'));
// Isolate the UI runner so the app project and release scheme need no test target.
writeFileSync(join(work, 'project.yml'), `
name: FeedbackUI
options:
  deploymentTarget:
    iOS: '27.0'
targets:
  FeedbackUICheck:
    type: bundle.ui-testing
    platform: iOS
    sources: [FeedbackUICheck.swift]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.gaoyiming.longshot.feedback-ui-tests
      GENERATE_INFOPLIST_FILE: YES
      SWIFT_VERSION: '5.0'
schemes:
  FeedbackUI:
    build:
      targets:
        FeedbackUICheck: [test]
    test:
      targets: [FeedbackUICheck]
`);
console.log(`Feedback UI test artifacts: ${work}`);
execFileSync('xcodegen', ['generate'], { cwd: work, stdio: 'inherit' });
execFileSync('xcrun', ['simctl', 'install', simulator, app], { stdio: 'inherit', timeout: 60_000 });
execFileSync('xcodebuild', ['-project', join(work, 'FeedbackUI.xcodeproj'), '-scheme', 'FeedbackUI',
  '-destination', `platform=iOS Simulator,id=${simulator}`, '-parallel-testing-enabled', 'NO',
  '-derivedDataPath', join(work, 'DerivedData'), '-resultBundlePath', join(work, 'FeedbackUI.xcresult'),
  'CODE_SIGNING_ALLOWED=NO', 'test'], { stdio: 'inherit', timeout: 300_000 });
