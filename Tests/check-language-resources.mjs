import assert from 'node:assert/strict';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const app = resolve(process.argv[2]);
function readStrings(path) {
  const result = spawnSync('plutil', ['-convert', 'json', '-o', '-', path], { encoding: 'utf8' });
  if (result.status !== 0) throw new Error(result.stderr);
  return JSON.parse(result.stdout);
}
for (const target of [app, join(app, 'PlugIns/LongScrollWidgets.appex')]) {
  const en = readStrings(join(target, 'en.lproj/Localizable.strings'));
  const zh = readStrings(join(target, 'zh-Hans.lproj/Localizable.strings'));
  assert.deepEqual(Object.keys(en).sort(), Object.keys(zh).sort());
  assert.equal(en['长卷'], 'Long Scroll');
  assert.equal(en['长卷 · 接下一页'], 'Long Scroll · Next page');
  assert.equal(zh['长卷'], '长卷');
  assert.equal(en['完成长卷'], 'Finish Long Scroll');
}
const permissionEn = readStrings(join(app, 'en.lproj/InfoPlist.strings'));
const permissionZh = readStrings(join(app, 'zh-Hans.lproj/InfoPlist.strings'));
assert.deepEqual(Object.keys(permissionEn).sort(), Object.keys(permissionZh).sort());
assert.ok(permissionEn.NSScreenCaptureUsageDescription.includes('explicitly share'));
assert.ok(permissionEn.NSPhotoLibraryAddUsageDescription.includes('photo library'));
console.log('Both signed targets contain Chinese/English control metadata; permission usage strings are bilingual');
