import assert from 'node:assert/strict';
import { assessPerformance, summarizeCompletion } from './regression-metrics.mjs';
const row = { sampling: 0.1, selection: 0.2, assembly: 0.3, rendering: 0.4, total: 1 };
const sample = { outputsByteIdentical: true, measuredPairs: 5, preparedFrameCount: 90, frameCount: 90,
  baseline: Array.from({ length: 5 }, () => ({ ...row })), current: Array.from({ length: 5 }, () => ({ ...row })) };
assert.equal(assessPerformance(sample).status, 'passed');
assert.equal(assessPerformance({ ...sample, current: sample.current.map(r => ({ ...r, total: 3 })) }).status, 'failed');
assert.throws(() => assessPerformance({ ...sample, outputsByteIdentical: false }));
assert.throws(() => assessPerformance({ ...sample, preparedFrameCount: 89 }));
assert.throws(() => assessPerformance({ ...sample, baseline: [] }));
assert.throws(() => assessPerformance({ ...sample, current: sample.current.map(r => ({ ...r, total: NaN })) }));
const timing = { schemaVersion: 2, sessionID: 'fixture', appVersion: '1.1.2', appBuild: '37', optimizedBuild: true,
  frameCount: 90, inputPageCount: 3, preparedFrameCount: 89, fallbackFrameCount: 1,
  finishToSavedSeconds: 3, stitchingSeconds: 2, samplingSeconds: 0.1, selectionSeconds: 0.2,
  assemblySeconds: 0.7, renderingSeconds: 1, photosWriteSeconds: 0.4 };
assert.equal(summarizeCompletion(timing).evidenceStatus, 'observed');
assert.equal(summarizeCompletion({ ...timing, optimizedBuild: false }).evidenceStatus, 'failed');
assert.equal(summarizeCompletion({ ...timing, finishToSavedSeconds: undefined }).evidenceStatus, 'incomplete');
assert.equal(summarizeCompletion({ ...timing, frameCount: 91 }).evidenceStatus, 'failed');
assert.equal(summarizeCompletion(timing, [{ sessionID: 'other', event: 'backgroundTimeExpired' }]).evidenceStatus, 'observed');
assert.equal(summarizeCompletion(timing, [{ sessionID: 'fixture', event: 'backgroundTimeExpired' }]).evidenceStatus, 'failed');
assert.equal(summarizeCompletion(timing, [{ sessionID: 'fixture', event: 'resultNotificationFinished' }]).bannerVisiblyPresented, 'not_verified');
assert.equal(summarizeCompletion(timing).values.captureStoppedToSavedSeconds, null);
assert.throws(() => summarizeCompletion({ ...timing, photosWriteSeconds: -1 }));
assert.throws(() => summarizeCompletion({ ...timing, schemaVersion: 99 }));
console.log('Regression report guard tests passed (16): failures, missing data and unverified banners cannot become a pass.');
