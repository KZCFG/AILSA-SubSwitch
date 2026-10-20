// Short-lived worker. Uses the original OpenCodex locked mutation, never a stale auth.json rewrite.
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";

export async function synchronize(original: any, input: any) {
  if (!original || typeof original.mutateStore !== "function" || typeof original.credentialGeneration !== "function") throw Error("unsupported_store");
  if (!["antigravity-pool", "google-antigravity"].includes(input.provider) || !Array.isArray(input.rows) || input.rows.length > 25) throw Error("invalid_request");
  const rows = input.rows;
  for (const row of rows) {
    const c = row.credential;
    if (!row.email || typeof row.email !== "string" || row.email !== row.email.trim().toLowerCase() ||
        !c || c.email !== row.email || typeof c.access !== "string" || !c.access || typeof c.refresh !== "string" || !c.refresh ||
        !Number.isSafeInteger(c.expires) || c.expires <= Date.now() || typeof c.projectId !== "string" || !c.projectId ||
        (!row.id && row.insert !== true) || (row.id && !row.expected)) throw Error("invalid_credential");
  }
  return await original.mutateStore((store: any) => {
    let inserted = 0, updated = 0, superseded = 0;
    const set = store[input.provider];
    if (!set || !Array.isArray(set.accounts)) throw Error("missing_pool");
    for (const row of rows) {
      const current = row.id ? set.accounts.find((a: any) => a.id === row.id) : undefined;
      if (row.id) {
        if (!current || current.credential.email?.toLowerCase() !== row.email ||
            original.credentialGeneration(current.credential) !== original.credentialGeneration(row.expected) ||
            current.credential.expires > row.credential.expires) { superseded++; continue; }
        current.credential = { ...current.credential, ...row.credential };
        // A human verification requirement remains owned by the provider.
        if (current.needsReauthReason !== "verify_account") delete current.needsReauth;
        updated++;
      } else {
        if (set.accounts.some((a: any) => a.credential.email?.toLowerCase() === row.email)) { superseded++; continue; }
        // Admission never participates in routing until the user checks the new row.
        set.accounts.push({id: randomUUID().replaceAll("-", ""), credential: row.credential, paused: true, addedAt: Date.now()});
        inserted++;
      }
    }
    return { inserted, updated, superseded };
  });
}

if (import.meta.main) {
  // Imported dependencies may log; no credential-bearing output may reach application logs.
  const write = process.stdout.write.bind(process.stdout);
  console.log = console.info = console.warn = console.error = () => {};
  try {
    const raw = await Bun.stdin.text();
    if (Buffer.byteLength(raw) > 256_000) throw Error("oversized_request");
    const input = JSON.parse(raw), root = resolve(process.argv[2] ?? "");
    const pkg = await Bun.file(root + "/package.json").json();
    if (pkg.name !== "@bitkyc08/opencodex") throw Error("unsupported_runtime");
    const config = await import(pathToFileURL(root + "/src/config.ts").href);
    if (resolve(config.getConfigDir()) !== resolve(input.home)) throw Error("wrong_home");
    const original = await import(pathToFileURL(root + "/src/oauth/store.ts").href);
    if (input.action === "probe") {
      if (typeof original.mutateStore !== "function" || typeof original.credentialGeneration !== "function") throw Error("unsupported_store");
      write('{"supported":true}\n');
    } else write(JSON.stringify(await synchronize(original, input)) + "\n");
  } catch { write('{"error":"sync_failed"}\n'); process.exitCode = 1; }
}
