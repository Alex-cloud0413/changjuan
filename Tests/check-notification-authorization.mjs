import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(resolve(testDirectory, "../LongShotApp/ResultNotificationManager.swift"), "utf8");
const temporaryDirectory = mkdtempSync(join(tmpdir(), "LongShotNotificationChecks-"));

function between(start, end) {
  const first = source.indexOf(start);
  const last = source.indexOf(end, first);
  if (first < 0 || last < 0) throw new Error(`Cannot locate production section: ${start}`);
  return source.slice(first, last);
}

const preparation = between("    func prepareAuthorizationIfNeeded()", "    /// Reads current system settings");
const refresh = between("    @discardableResult\n    func refreshSettingsSnapshot()", "    func postSavedResult(");
const snapshotMethods = between("    private func makeSettingsSnapshot(", "    private func writeNotificationPreview(");
const isolatedMethods = snapshotMethods.replace(
  "FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]",
  "URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)"
);
if (isolatedMethods === snapshotMethods) throw new Error("Snapshot output isolation failed");
const snapshot = between("struct ResultNotificationSettingsSnapshot: Codable", "/// Persistent, one-result handoff.");
const harness = `import Foundation
${snapshot}
@MainActor
final class ResultNotificationManager {
    private let center: UNUserNotificationCenter
    private var authorizationPreparationInFlight = false
    init(center: UNUserNotificationCenter) { self.center = center }
${preparation}
${refresh}
${isolatedMethods}
}
`;
const generatedSource = join(temporaryDirectory, "ProductionAuthorizationMethods.swift");
writeFileSync(generatedSource, harness);

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
  return result.stdout.trim();
}

const swift = spawnSync("xcrun", ["--find", "swiftc"], { encoding: "utf8" });
const sdk = spawnSync("xcrun", ["--sdk", "macosx", "--show-sdk-path"], { encoding: "utf8" });
if (swift.status !== 0 || sdk.status !== 0) throw new Error(swift.stderr || sdk.stderr || "Xcode toolchain unavailable");
const binary = join(temporaryDirectory, "notification-authorization-checks");
run(swift.stdout.trim(), [
  "-swift-version", "5", "-target", `${process.arch === "arm64" ? "arm64" : "x86_64"}-apple-macosx13.0`,
  "-sdk", sdk.stdout.trim(), "-module-cache-path", join(temporaryDirectory, "module-cache"),
  generatedSource, join(testDirectory, "NotificationAuthorizationCheck.swift"), "-o", binary,
]);
run(binary, [temporaryDirectory]);
console.log(`Isolated metadata fixtures: ${temporaryDirectory}`);
