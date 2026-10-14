import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Source-level presentation checks, not a substitute for native UI inspection.
const view = readFileSync(new URL('../LongShotApp/ContentView.swift', import.meta.url), 'utf8');
assert.ok(!view.includes('Text("把滚动，收成一卷")'), 'Home tagline must be removed');
assert.ok(!view.includes('Text(captureActionTitle)'), 'Idle action must not show its title');
assert.ok(view.includes('if let title = visibleCaptureActionTitle'), 'Active states retain title rendering');
assert.match(view, /private var visibleCaptureActionTitle: String\?\s*\{\s*switch model\.phase\s*\{\s*case \.idle, \.ready, \.failed:\s*return nil\s*case \.choosingSource, \.capturing, \.processing:\s*return captureActionTitle/);
assert.ok(view.includes('.accessibilityLabel(captureActionTitle)'), 'Icon-only button retains VoiceOver action label');
assert.ok(view.includes('.frame(width: 88, height: 88)'), 'Capture target remains larger than 44 points');
assert.ok(view.includes('.accessibilityIdentifier("home.usageGuide")'), 'Guide remains discoverable');
assert.ok(view.includes('Task { await model.stopCapture() }') && view.includes('model.beginCapture()'), 'Capture actions remain wired');
console.log('Home icon-only presentation checks passed (8); runtime layout and interaction are separate checks.');
