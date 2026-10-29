import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { zstdCompressSync } from 'node:zlib';
import { project, scan, completePrefix } from '../../Sources/AILSA_SS/Resources/AILSA_SS-DeepSeekHarnessUsage.mjs';
const header={type:'session',version:4,id:'s',cwd:'private-folder'};
const event=(seq=1,usage={inputTokens:10,outputTokens:20,cacheReadTokens:40,totalTokens:70})=>({type:'assistant/message',seq,time:1793325600000,data:{turn:1,step:1,message:{content:'DO NOT EXPORT THIS PROMPT',source:{provider:'deepseek-official',model:'deepseek-flash',replayState:{response:{responseId:'r'}}}},usage,stream:[{chunk:{usage}}]}});
const lines=rows=>rows.map(x=>JSON.stringify(x)+'\n').join('');
function directory(t){const root=fs.mkdtempSync(path.join(os.tmpdir(),'harness-usage-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));return root;}
test('counts settlement once, not repeated stream usage; exports metadata only',()=>{
 const result=project(lines([header,event()]));assert.equal(result.records.length,1);
 assert.equal(result.records[0].usage.totalTokens,70);assert.ok(!JSON.stringify(result).includes('DO NOT EXPORT'));assert.ok(!JSON.stringify(result).includes('private-folder'));
});
test('replaces newer settlement while preserving a billed retry',()=>{
 const result=project(lines([header,event(),event(2),{type:'llm/retry-started',data:{turn:1,step:1}},event(3)]));
 assert.equal(result.records.length,2);assert.equal(result.records[0].seq,2);
});
test('attempt uses final reported stream sample',()=>{
 const attempt={type:'assistant/attempt',seq:2,time:1793325600000,data:{turn:1,step:1,stream:[{chunk:{usage:{inputTokens:10,outputTokens:3}}},{chunk:{usage:{inputTokens:10,outputTokens:8}}}]}};
 const result=project(lines([header,{type:'request/header',data:{header:{config:{provider:'deepseek-official',model:'deepseek-flash'}}}},attempt]));
 assert.equal(result.records[0].usage.outputTokens,8);assert.equal(result.records[0].requestedOnly,true);
});
test('reads every concatenated Zstandard frame, including the event after the header',t=>{
 const root=directory(t),h=zstdCompressSync(lines([header])),e=zstdCompressSync(lines([event()]));
 fs.writeFileSync(path.join(root,'session.v4.jsonl.zstd'),Buffer.concat([h,e]));
 const result=scan(root);assert.equal(result.records.length,1);assert.equal(result.partial,false);assert.equal(completePrefix(Buffer.concat([h,e])),h.length+e.length);
});
test('torn final frame keeps verified earlier records and marks partial',t=>{
 const root=directory(t),h=zstdCompressSync(lines([header,event()])),tail=zstdCompressSync(lines([event(2)]));
 fs.writeFileSync(path.join(root,'session.v4.jsonl.zstd'),Buffer.concat([h,tail.subarray(0,tail.length-2)]));
 const result=scan(root);assert.equal(result.records.length,1);assert.equal(result.partial,true);
});
test('incomplete JSON, unsupported version and invalid counters never become complete records',()=>{
 assert.equal(project(lines([header])+JSON.stringify(event())).records.length,0);
 assert.equal(project(lines([{...header,version:5},event()])).records.length,0);
 assert.equal(project(lines([header,event(1,{inputTokens:-1,outputTokens:3})])).records.length,0);
});
test('does not follow session symlinks or read credential files',t=>{
 const root=directory(t),outside=directory(t);fs.writeFileSync(path.join(outside,'session.v4.jsonl'),lines([header,event()]));
 fs.symlinkSync(outside,path.join(root,'linked'));fs.writeFileSync(path.join(root,'.credentials.yaml'),'secret');
 assert.equal(scan(root).files,0);
});

test('request start owns the pricing timestamp across a peak/off-peak boundary',()=>{
 const e=event();e.time=Date.parse('2026-10-30T04:00:30Z');
 const start={type:'step/start',seq:0,time:Date.parse('2026-10-30T03:59:59Z'),data:{turn:1,step:1}};
 const value=project(lines([header,start,e])).records[0];assert.equal(value.time,start.time);assert.equal(value.timeEstimated,false);
 assert.equal(project(lines([header,e])).records[0].timeEstimated,true);
});
