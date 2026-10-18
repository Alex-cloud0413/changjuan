import assert from 'node:assert/strict';

export function percentile(values, fraction) {
  assert.ok(values.length > 0 && values.every(value => Number.isFinite(value) && value >= 0));
  return [...values].sort((a, b) => a - b)[Math.ceil(values.length * fraction) - 1];
}

// Noise allowance, not a user-visible performance promise. Run serially on an
// idle host; never use this simulator budget for finish-to-Photos device timing.
export function assessPerformance(sample) {
  assert.equal(sample.outputsByteIdentical, true);
  assert.equal(sample.measuredPairs, 5);
  assert.equal(sample.preparedFrameCount, sample.frameCount);
  const stages = {};
  for (const key of ['sampling', 'selection', 'assembly', 'rendering', 'total']) {
    assert.equal(sample.baseline.length, 5);
    assert.equal(sample.current.length, 5);
    const before = sample.baseline.map(row => row[key]);
    const after = sample.current.map(row => row[key]);
    const medianBefore = percentile(before, 0.5), medianAfter = percentile(after, 0.5);
    const p95Before = percentile(before, 0.95), p95After = percentile(after, 0.95);
    stages[key] = { medianBefore, medianAfter, p95Before, p95After,
      medianBudget: medianBefore * 1.20 + 0.15, p95Budget: p95Before * 1.35 + 0.30 };
  }
  const regressions = Object.entries(stages).filter(([, s]) =>
    s.medianAfter > s.medianBudget || s.p95After > s.p95Budget).map(([name]) => name);
  return { status: regressions.length ? 'failed' : 'passed', regressions, stages,
    scope: 'optimized simulator algorithm; warm cache; not finish-to-Photos',
    caveat: 'Five samples: p95 is the sample maximum, not a reliable population tail estimate.' };
}

export function summarizeCompletion(timing, events = []) {
  assert.equal(timing.schemaVersion, 2, 'Unsupported/missing completion schema');
  assert.equal(typeof timing.sessionID, 'string');
  assert.ok(timing.sessionID.length > 0);
  assert.ok(Array.isArray(events));
  const fields = ['frameCount', 'inputPageCount', 'preparedFrameCount', 'fallbackFrameCount',
    'finishToSavedSeconds', 'captureStoppedToSavedSeconds', 'stitchingSeconds', 'samplingSeconds',
    'selectionSeconds', 'assemblySeconds', 'renderingSeconds', 'photosAuthorizationSeconds',
    'photosWriteSeconds', 'photosCallbackResumeSeconds', 'stitchDispatchDelaySeconds', 'stitchReturnDelaySeconds'];
  const values = {};
  for (const key of fields) {
    if (timing[key] === undefined) { values[key] = null; continue; }
    assert.ok(Number.isFinite(timing[key]) && timing[key] >= 0, `Invalid ${key}`);
    values[key] = timing[key];
  }
  const missing = ['frameCount', 'inputPageCount', 'preparedFrameCount', 'fallbackFrameCount',
    'stitchingSeconds', 'samplingSeconds', 'selectionSeconds', 'assemblySeconds', 'renderingSeconds',
    'photosWriteSeconds'].filter(key => values[key] === null);
  if (values.finishToSavedSeconds === null) missing.push('finishToSavedSeconds');
  const problems = [];
  if (timing.optimizedBuild !== true) problems.push('not-confirmed-Release-optimized');
  if (values.frameCount !== null && values.preparedFrameCount !== null && values.fallbackFrameCount !== null &&
      values.preparedFrameCount + values.fallbackFrameCount !== values.frameCount) problems.push('frame-accounting-mismatch');
  const sessionEvents = events.filter(row => row.sessionID === timing.sessionID);
  if (sessionEvents.some(row => row.event === 'backgroundTimeExpired')) problems.push('background-time-expired');
  if (sessionEvents.some(row => row.event === 'processingFailed')) problems.push('processing-failed');
  return { appVersion: timing.appVersion ?? null, appBuild: timing.appBuild ?? null,
    optimizedBuild: timing.optimizedBuild === true, values, missing, problems,
    evidenceStatus: problems.length ? 'failed' : missing.length ? 'incomplete' : 'observed',
    notificationCallFinished: sessionEvents.some(row => row.event === 'resultNotificationFinished'),
    bannerVisiblyPresented: 'not_verified',
    performanceVerdict: 'not_comparable_without_matched_device_scenarios',
    // Intentionally do not emit session IDs, paths, screen content or raw events.
  };
}
