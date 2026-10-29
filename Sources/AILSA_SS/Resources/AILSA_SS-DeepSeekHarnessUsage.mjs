// Read-only usage projection. Runs in the installed Harness Node runtime.
// No Harness plugins, credentials, configuration, prompts or network clients are loaded.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { zstdDecompressSync } from 'node:zlib';

const MAX_FILE = 32 * 1024 * 1024, MAX_TEXT = 128 * 1024 * 1024;
const MAX_FILES = 4096, MAX_RECORDS = 200000;
// Zstandard framing: decode only complete frames, including checksum validation.
// A writer's incomplete final frame is retried on the next scan, never repaired.
function completeFrames(bytes) {
  let cursor = 0; const ranges=[];
  while (cursor < bytes.length) {
    const start=cursor;
    if (bytes.length - cursor < 5) break;
    if (bytes.readUInt32LE(cursor) !== 0xfd2fb528) throw Error('unsupported frame');
    const flags = bytes[cursor + 4];
    if (flags & 24) throw Error('reserved frame bits');
    cursor += 5;
    const single = !!(flags & 32), sizeFlag = flags >>> 6;
    const headerBytes = (single ? 0 : 1) + [0, 1, 2, 4][flags & 3]
      + (sizeFlag ? 2 ** sizeFlag : single ? 1 : 0);
    if (cursor + headerBytes > bytes.length) break;
    cursor += headerBytes;
    let complete = false;
    while (cursor + 3 <= bytes.length) {
      const block = bytes.readUIntLE(cursor, 3), kind = (block >>> 1) & 3;
      if (kind === 3) throw Error('reserved block');
      cursor += 3 + (kind === 1 ? 1 : block >>> 3);
      if (cursor > bytes.length) break;
      if (block & 1) { complete = true; break; }
    }
    if (!complete) break;
    cursor += flags & 4 ? 4 : 0;
    if (cursor > bytes.length) break;
    ranges.push([start,cursor]);
  }
  return ranges;
}

export function completePrefix(bytes) { return completeFrames(bytes).at(-1)?.[1] ?? 0; }

function usageOf(data) {
  if (data.usage && typeof data.usage === 'object') return data.usage;
  return data.stream?.findLast(x => x?.chunk?.usage)?.chunk.usage;
}
const counters = ['inputTokens', 'outputTokens', 'totalTokens', 'cacheReadTokens', 'cacheWriteTokens', 'reasoningTokens'];
const cleanUsage = value => Object.fromEntries(counters.filter(k => Object.hasOwn(value, k)).map(k => [k, value[k]]));

export function project(text) {
  let session, partial = false, config = {}, epoch = new Map(), started = new Map(), slots = new Map();
  for (const line of text.split('\n').slice(0, -1)) {
    if (!line) continue;
    let event;
    try { event = JSON.parse(line); } catch { partial = true; continue; }
    if (event.type === 'session') {
      if (event.version !== 4 || typeof event.id !== 'string') return { records: [], partial: true };
      if (session && session !== event.id) return { records: [], partial: true };
      session = event.id; continue;
    }
    if (!session) { partial = true; continue; }
    const d = event.data ?? {};
    if (event.type === 'request/header') config = d.header?.config ?? {};
    const slot = `${d.turn}:${d.step}`;
    if (event.type === 'step/start' && Number.isSafeInteger(event.time)) {
      started.set(`${slot}:${epoch.get(slot) ?? 0}`,event.time);continue;
    }
    if (event.type === 'llm/retry-started') {
      const next=(epoch.get(slot) ?? 0)+1;epoch.set(slot,next);
      if (Number.isSafeInteger(event.time)) started.set(`${slot}:${next}`,event.time);continue;
    }
    if (!['assistant/message', 'assistant/attempt'].includes(event.type)) continue;
    const usage = usageOf(d);
    if (!usage) continue;
    if (!["inputTokens","outputTokens"].every(k=>Number.isSafeInteger(usage[k]) && usage[k]>=0) || counters.some(k=>Object.hasOwn(usage,k) && (!Number.isSafeInteger(usage[k]) || usage[k]<0))) {partial=true;continue;}
    if (![d.turn, d.step, event.seq, event.time].every(Number.isSafeInteger)) { partial = true; continue; }
    const source = d.message?.source ?? {};
    const replay = source.replayState?.response ?? d.stream?.findLast(x => x?.chunk?.replayState?.response)?.chunk.replayState.response ?? {};
    const provider = source.provider ?? replay.provider ?? config.provider;
    const model = source.model ?? replay.model ?? config.model;
    if (typeof provider !== 'string' || typeof model !== 'string') { partial = true; continue; }
    const record = { session, turn: d.turn, step: d.step, epoch: epoch.get(slot) ?? 0,
      seq: event.seq, time: started.get(`${slot}:${epoch.get(slot) ?? 0}`) ?? event.time, provider, model, usage: cleanUsage(usage),
      timeEstimated: !started.has(`${slot}:${epoch.get(slot) ?? 0}`),
      requestedOnly: !source.model && !replay.model };
    if (typeof d.message?.id === 'string') record.messageID=d.message.id;
    if (typeof replay.responseId === 'string') record.responseID = replay.responseId;
    if (typeof replay.responseModel === 'string') record.responseModel = replay.responseModel;
    const identity = `${slot}:${record.epoch}`;
    if (!slots.has(identity) || slots.get(identity).seq <= record.seq) slots.set(identity, record);
    if (slots.size > MAX_RECORDS) throw Error('record limit');
  }
  if (text && !text.endsWith('\n')) partial = true;
  return { records: [...slots.values()], partial };
}

export function scan(root) {
  let files = 0, partial = false, records = [], bytes = 0;
  if (!fs.existsSync(root)) return { version: 1, files, partial, records };
  function visit(directory, depth) {
    if (depth > 8) { partial = true; return; }
    for (const item of fs.readdirSync(directory, { withFileTypes: true }).sort((a,b) => a.name.localeCompare(b.name))) {
      const name = path.join(directory, item.name);
      if (item.isSymbolicLink()) continue;
      if (item.isDirectory()) { visit(name, depth + 1); continue; }
      if (!item.isFile() || !['session.v4.jsonl', 'session.v4.jsonl.zstd'].includes(item.name)) continue;
      if (++files > MAX_FILES) { partial = true; return; }
      try {
        const stat = fs.statSync(name);
        if (stat.size > MAX_FILE || bytes + stat.size > 512 * 1024 * 1024) throw Error('file limit');
        bytes += stat.size;
        const data = fs.readFileSync(name);
        let plain = data;
        if (item.name.endsWith('.zstd')) {
          const frames = completeFrames(data), end = frames.at(-1)?.[1] ?? 0;
          partial ||= end !== data.length;
          const parts=[];let length=0;
          for (const [start,end] of frames) {
            const part=zstdDecompressSync(data.subarray(start,end), { maxOutputLength: MAX_TEXT-length });
            length+=part.length;if (length>MAX_TEXT) throw Error('text limit');parts.push(part);
          }
          plain=Buffer.concat(parts,length);
        }
        const value = project(plain.toString('utf8'));
        partial ||= value.partial;
        records.push(...value.records);
        if (records.length > MAX_RECORDS) throw Error('record limit');
        const after = fs.statSync(name);
        partial ||= stat.size !== after.size || stat.mtimeMs !== after.mtimeMs;
      } catch { partial = true; }
    }
  }
  visit(root, 0);
  return { version: 1, files: Math.min(files,MAX_FILES), partial, records };
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.stdout.write(JSON.stringify(scan(process.argv[2]))); }
  catch { process.stdout.write(JSON.stringify({version:1,files:0,partial:true,records:[]})); process.exitCode=1; }
}
