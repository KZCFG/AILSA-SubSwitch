import { test, expect } from "bun:test";
import { synchronize } from "../../Sources/AILSA_SS/Resources/OpenCodexManagedSync.ts";
const cred = (email = "a@example.com", refresh = "fixture-old", expires = Date.now() + 3600000) => ({email, access: "fixture-access", refresh, expires, projectId: "own-project"});
const api = (store: any) => ({calls: 0, credentialGeneration: (c: any) => JSON.stringify([c.refresh, c.access, c.expires]), async mutateStore(fn: any) { this.calls++; return fn(store); }});
test("native locked mutation preserves active choice, labels, pause flags and unrelated providers", async () => {
  const old = cred(), next = {...old, refresh: "fixture-new", expires: old.expires + 1000};
  const store = {"antigravity-pool": {activeAccountId: "b", accounts: [{id: "a", alias: "custom", paused: true, credential: {...old, plan: "paid"}}]}, other: {untouched: true}};
  const original = api(store);
  const result = await synchronize(original, {provider: "antigravity-pool", rows: [{id: "a", email: old.email, expected: old, credential: next}]});
  expect(result.updated).toBe(1); expect(original.calls).toBe(1);
  expect(store["antigravity-pool"].activeAccountId).toBe("b"); expect(store["antigravity-pool"].accounts[0].paused).toBe(true);
  expect(store["antigravity-pool"].accounts[0].credential.plan).toBe("paid"); expect(store.other.untouched).toBe(true);
});
test("changed generation or newer proxy grant is never overwritten", async () => {
  const old = cred(), store = {"antigravity-pool": {activeAccountId: "a", accounts: [{id: "a", credential: {...old, refresh: "concurrent-refresh"}}]}};
  const result = await synchronize(api(store), {provider: "antigravity-pool", rows: [{id: "a", email: old.email, expected: old, credential: {...old, refresh: "stale"}}]});
  expect(result.superseded).toBe(1); expect(store["antigravity-pool"].accounts[0].credential.refresh).toBe("concurrent-refresh");
});
test("new admission is paused and never changes active id", async () => {
  const c = cred("new@example.com"), store = {"antigravity-pool": {activeAccountId: "kept", accounts: [] as any[]}};
  const result = await synchronize(api(store), {provider: "antigravity-pool", rows: [{insert: true, email: c.email, credential: c}]});
  expect(result.inserted).toBe(1); expect(store["antigravity-pool"].accounts[0].paused).toBe(true); expect(store["antigravity-pool"].activeAccountId).toBe("kept");
});
test("unsupported provider and invalid identity fail before a store transaction", async () => {
  const original = api({});
  await expect(synchronize(original, {provider: "other", rows: []})).rejects.toThrow();
  await expect(synchronize(original, {provider: "antigravity-pool", rows: [{insert:true, email:"wrong@example.com", credential:cred()}]})).rejects.toThrow();
  expect(original.calls).toBe(0);
});
test("provider verification requirements are retained", async () => {
  const c = cred(), row = {id: "a", credential: c, needsReauth: true, needsReauthReason: "verify_account"};
  await synchronize(api({"antigravity-pool": {activeAccountId:"a", accounts:[row]}}), {provider:"antigravity-pool",rows:[{id:"a",email:c.email,expected:c,credential:{...c,refresh:"new"}}]});
  expect(row.needsReauth).toBe(true); expect(row.needsReauthReason).toBe("verify_account");
});
