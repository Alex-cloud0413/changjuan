import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

// Uses production source and an isolated temp container. Never reads or clears
// the installed app's recordings, Photos, notification settings or defaults.
const testDirectory = dirname(fileURLToPath(import.meta.url));
const project = resolve(testDirectory, "..");
const simulator = process.argv[2];
if (!simulator) throw new Error("Pass the UDID of a booted iOS 27 simulator");
const work = mkdtempSync(join(tmpdir(), "LongShotImprovementsChecks-"));
function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited ${result.status}`);
  return result.stdout.trim();
}
const sdk = run("xcrun", ["--sdk", "iphonesimulator", "--show-sdk-path"]);
const swift = run("xcrun", ["--find", "swiftc"]);
const common = ["-O", "-swift-version", "5", "-target", "arm64-apple-ios27.0-simulator", "-sdk", sdk,
  "-module-cache-path", join(work, "module-cache")];
function compile(name, sources, flags = []) {
  const binary = join(work, name);
  run(swift, [...common, ...flags, ...sources, "-o", binary]);
  return binary;
}
const shared = name => join(project, "Shared", name);
const app = name => join(project, "LongShotApp", name);
const source = readFileSync(app("ScreenCaptureCoordinator.swift"), "utf8");
const first = source.indexOf("final class ScreenCaptureHostVisibility:");
const last = source.indexOf("\n#else\n/// ScreenCaptureKit is device-only", first);
if (first < 0 || last < 0) throw new Error("Cannot extract the production serial pipeline");
const extracted = join(work, "ProductionScreenFramePipeline.swift");
writeFileSync(extracted, "import CoreImage\nimport CoreMedia\nimport Foundation\nimport ImageIO\nimport UIKit\n" + source.slice(first, last));
const pipeline = compile("pipeline", [shared("CaptureConstants.swift"), shared("CaptureStorage.swift"),
  shared("OverlapEstimator.swift"), shared("HorizontalTableMatcher.swift"), app("FrameStitcher.swift"), app("FramePreparationCache.swift"), extracted,
  join(testDirectory, "ScreenFramePipelineCheck.swift")], ["-D", "LONGSHOT_CAPTURE_CHECKS", "-D", "LONGSHOT_SCK_METADATA_STUB"]);
run("xcrun", ["simctl", "spawn", simulator, pipeline]);
const baselineSources = [];
const baselineFlags = [];
if (process.env.LONGSHOT_STITCH_BASELINE) {
  const rename = source => source.replace(
    /\b(FrameStitcher|StitchError|StitchResult|StitchTimings|CaptureOverlayDetector|FramePreparationCache|PreparedFrame|FramePreprocessor)\b/g,
    name => `Legacy${name}`
  );
  // A pinned pair prevents a new cache reader from masking regressions in the
  // previous release. Legacy and current receive exactly the same JPEGs.
  if (!process.env.LONGSHOT_CACHE_BASELINE) throw new Error("Pass the baseline cache source with the stitcher");
  const legacy = rename(readFileSync(process.env.LONGSHOT_STITCH_BASELINE, "utf8"));
  const legacyFile = join(work, "LegacyFrameStitcher.swift");
  writeFileSync(legacyFile, legacy);
  baselineSources.push(legacyFile);
  const legacyCache = join(work, "LegacyFramePreparationCache.swift");
  // Keep independently generated legacy analysis beside, not over, the new
  // cache revision. Both timed implementations must receive a warm cache.
  const originalLegacyCache = rename(readFileSync(process.env.LONGSHOT_CACHE_BASELINE, "utf8"));
  assert.ok(originalLegacyCache.includes('"Analysis-v1"'), 'Locate pinned baseline cache namespace before isolating it');
  const isolatedLegacyCache = originalLegacyCache.replaceAll('"Analysis-v1"', '"LegacyAnalysis-v1"');
  assert.ok(isolatedLegacyCache.includes('"LegacyAnalysis-v1"') && !isolatedLegacyCache.includes('"Analysis-v1"'),
    'Legacy timing must never read or overwrite current analysis files');
  writeFileSync(legacyCache, isolatedLegacyCache);
  baselineSources.push(legacyCache);
  baselineFlags.push("-D", "LONGSHOT_BASELINE_CHECKS");
}
const stitcher = compile("stitcher", [shared("CaptureConstants.swift"), shared("CaptureStorage.swift"),
  shared("OverlapEstimator.swift"), shared("HorizontalTableMatcher.swift"), app("FrameStitcher.swift"), app("FramePreparationCache.swift"),
  ...baselineSources, join(testDirectory, "FrameStitcherBoundaryCheck.swift")],
  ["-D", "LONGSHOT_CAPTURE_CHECKS", ...baselineFlags]);
run("xcrun", ["simctl", "spawn", simulator, stitcher, "--nonperiodic", ...(process.argv[3] ? [process.argv[3]] : [])]);
const viewSource = readFileSync(app("ContentView.swift"), "utf8");
const previewStart = viewSource.indexOf("private struct ZoomableLongImage:");
const previewEnd = viewSource.indexOf("\nstruct CaptureSettingsView:", previewStart);
if (previewStart < 0 || previewEnd < 0) throw new Error("Cannot extract actual preview layout");
const preview = join(work, "ProductionPreview.swift");
writeFileSync(preview, "import SwiftUI\nimport UIKit\n" + viewSource.slice(previewStart, previewEnd)
  .replace("private struct ZoomableLongImage:", "struct ZoomableLongImage:"));
const options = compile("options", [shared("CaptureConstants.swift"), shared("CaptureStorage.swift"),
  shared("OverlapEstimator.swift"), shared("HorizontalTableMatcher.swift"), app("FrameStitcher.swift"), app("FramePreparationCache.swift"),
  preview, join(testDirectory, "CaptureOptionsCheck.swift")], ["-D", "LONGSHOT_CAPTURE_CHECKS"]);
run("xcrun", ["simctl", "spawn", simulator, options]);
const visual = compile("visual", [shared("AppLanguage.swift"), shared("CaptureSystemIntegration.swift"),
  join(project, "LongScrollWidgets", "LongScrollLiveActivity.swift"), join(testDirectory, "CaptureActivityVisualCheck.swift")],
  ["-D", "LONGSHOT_SCREEN_CAPTURE_KIT"]);
run("xcrun", ["simctl", "spawn", simulator, visual, work]);
console.log(`Checks and actual SwiftUI row renders: ${work}`);
