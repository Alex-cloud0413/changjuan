import { readFileSync } from 'node:fs';
import { summarizeCompletion } from './regression-metrics.mjs';
if (!process.argv[2]) throw new Error('Usage: node Tests/summarize-completion-timing.mjs <exported LongShotCompletionTiming.json> [exported LongShotProcessingEvents.json]');
// Read-only, explicitly provided local exports only. Does not connect to a phone.
const summary = summarizeCompletion(JSON.parse(readFileSync(process.argv[2], 'utf8')),
  process.argv[3] ? JSON.parse(readFileSync(process.argv[3], 'utf8')) : []);
console.log(JSON.stringify(summary, null, 2));
if (summary.evidenceStatus === 'failed') process.exitCode = 1;
else if (summary.evidenceStatus === 'incomplete') process.exitCode = 2;
