import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const tests = dirname(fileURLToPath(import.meta.url));
const root = resolve(tests, '..');
const source = readFileSync(join(root, 'Shared/AppLanguage.swift'), 'utf8');
const keys = new Set([...source.matchAll(/^        "([^"]+)": "/gm)].map(match => match[1]));
for (const name of ['LongShotApp/ContentView.swift', 'LongShotApp/UsageGuideView.swift', 'LongScrollWidgets/LongScrollLiveActivity.swift']) {
  const view = readFileSync(join(root, name), 'utf8');
  for (const [, literal] of view.matchAll(/"((?:[^"\\]|\\.)*)"/g)) {
    if (!/\p{Script=Han}/u.test(literal) || literal === '中文') continue;
    assert.ok(keys.has(literal), `${name}: missing English translation: ${literal}`);
  }
}
const home = readFileSync(join(root, 'LongShotApp/ContentView.swift'), 'utf8');
assert.ok(home.indexOf('languageButton(.chinese') < home.indexOf('languageButton(.english'), 'Chinese remains left of English');
assert.ok(home.includes('@AppStorage(AppLanguage.preferenceKey, store: AppLanguage.defaults)'));
assert.ok(home.includes('.accessibilityAddTraits(language == option ? .isSelected : [])'));
assert.ok(!home.includes('.id(languageCode)'), 'Switching must not recreate the capture view or session');
assert.ok(!source.includes('set("AppleLanguages"'), 'System language is not changed');
const model = readFileSync(join(root, 'LongShotApp/AppModel.swift'), 'utf8');
const refresh = model.split('func refreshLanguagePresentation() {')[1].split('\n    }')[0];
assert.ok(!/beginCapture|stopCapture|discard|setState/.test(refresh));

function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) throw new Error(`${command} failed: ${result.status}`);
  return result.stdout.trim();
}
const work = mkdtempSync(join(tmpdir(), 'LongShotLanguageChecks-'));
const swift = run('xcrun', ['--find', 'swiftc']);
const sdk = run('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
const binary = join(work, 'language-checks');
run(swift, ['-swift-version', '5', '-target', 'arm64-apple-macosx13.0', '-sdk', sdk,
  '-module-cache-path', join(work, 'cache'), join(root, 'Shared/AppLanguage.swift'), join(tests, 'AppLanguageCheck.swift'), '-o', binary]);
run(binary, [`longshot.test.language.${work.split('/').at(-1)}`]);
const restartSuite = `longshot.test.restart.${work.split('/').at(-1)}`;
run(binary, [restartSuite, '--write']);
run(binary, [restartSuite, '--read']);
console.log('UI translation coverage, selector order, state-preservation and persistence checks passed');
