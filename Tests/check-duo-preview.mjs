import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
const device = process.argv[2];
if (!device) throw new Error('Pass a booted iOS 27 simulator UDID');
const root = resolve(import.meta.dirname, '..');
const work = mkdtempSync(join(tmpdir(), 'LongShotDuoPreview-'));
const source = readFileSync(join(root, 'LongShotApp/ContentView.swift'), 'utf8');
const start = source.indexOf('private struct ZoomableLongImage:');
const end = source.indexOf('\nstruct CaptureSettingsView:', start);
if (start < 0 || end < start) throw new Error('Production preview not found');
const extracted = join(work, 'ProductionPreview.swift');
writeFileSync(extracted, 'import SwiftUI\nimport UIKit\n' + source.slice(start, end).replace('private struct ZoomableLongImage:', 'struct ZoomableLongImage:'));
const sdk = execFileSync('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-path'], { encoding: 'utf8' }).trim();
const binary = join(work, 'duo-preview');
execFileSync('xcrun', ['swiftc', '-O', '-swift-version', '5', '-target', 'arm64-apple-ios27.0-simulator', '-sdk', sdk,
  '-module-cache-path', join(work, 'cache'), extracted, join(root, 'Tests/DuoPreviewLayoutCheck.swift'), '-o', binary], { stdio: 'inherit' });
execFileSync('xcrun', ['simctl', 'spawn', device, binary], { stdio: 'inherit', timeout: 60_000 });
