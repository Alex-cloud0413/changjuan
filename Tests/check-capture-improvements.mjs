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
const pipeline = compile("pipeline", [shared("CaptureConstants.swift"), shared("CaptureStorage.swift"), extracted,
  join(testDirectory, "ScreenFramePipelineCheck.swift")], ["-D", "LONGSHOT_CAPTURE_CHECKS", "-D", "LONGSHOT_SCK_METADATA_STUB"]);
run("xcrun", ["simctl", "spawn", simulator, pipeline]);
const stitcher = compile("stitcher", [shared("CaptureConstants.swift"), shared("CaptureStorage.swift"),
  shared("OverlapEstimator.swift"), app("FrameStitcher.swift"), join(testDirectory, "FrameStitcherBoundaryCheck.swift")]);
run("xcrun", ["simctl", "spawn", simulator, stitcher, "--nonperiodic", ...(process.argv[3] ? [process.argv[3]] : [])]);
const visual = compile("visual", [shared("CaptureSystemIntegration.swift"),
  join(project, "LongScrollWidgets", "LongScrollLiveActivity.swift"), join(testDirectory, "CaptureActivityVisualCheck.swift")],
  ["-D", "LONGSHOT_SCREEN_CAPTURE_KIT"]);
run("xcrun", ["simctl", "spawn", simulator, visual, work]);
console.log(`Checks and actual SwiftUI row renders: ${work}`);
