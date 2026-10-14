import { cpSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Build a disposable screenshot target, never the shipping target. The views
// and stitcher remain production source; only initial presentation is seeded.
const tools = dirname(fileURLToPath(import.meta.url));
const project = resolve(tools, '..');
const work = mkdtempSync(join(tmpdir(), 'LongShotStoreScreenshots-'));
for (const name of ['LongShot.xcodeproj', 'Config', 'Shared', 'LongShotApp', 'LongScrollWidgets']) {
  cpSync(join(project, name), join(work, name), { recursive: true });
}
cpSync(join(tools, 'StoreScreenshotApp.swift'), join(work, 'LongShotApp', 'LongShotApp.swift'));
function replace(path, from, to) {
  const file = join(work, path);
  const source = readFileSync(file, 'utf8');
  if (!source.includes(from)) throw new Error(`Missing screenshot seed anchor: ${path}`);
  writeFileSync(file, source.replace(from, to));
}
replace('LongShotApp/ContentView.swift', 'private struct LongImagePreview:', 'struct LongImagePreview:');
replace('LongShotApp/UsageGuideView.swift', '@State private var selectedStep = 0',
  '@State private var selectedStep = ProcessInfo.processInfo.arguments.firstIndex(of: "--guide").flatMap { index in\n        let args = ProcessInfo.processInfo.arguments\n        return args.indices.contains(index + 1) ? Int(args[index + 1]) : nil\n    } ?? 0');
replace('Config/App.xcconfig', 'com.gaoyiming.longshot.private', 'com.gaoyiming.longshot.StorePreview');
replace('Config/Widgets.xcconfig', 'com.gaoyiming.longshot.private.Widgets', 'com.gaoyiming.longshot.StorePreview.Widgets');
replace('Config/Shared.xcconfig', 'group.com.gaoyiming.longshot.private', 'group.com.gaoyiming.longshot.StorePreview');
console.log(work);
