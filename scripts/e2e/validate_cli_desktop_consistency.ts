import { createAdminApi } from '../../apps/desktop/src/api/admin';

type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue };

function sortObject(value: JsonValue): JsonValue {
  if (Array.isArray(value)) {
    return value.map(sortObject);
  }
  if (value && typeof value === 'object') {
    const entries = Object.entries(value).sort(([a], [b]) => a.localeCompare(b));
    const sorted: Record<string, JsonValue> = {};
    for (const [key, entryValue] of entries) {
      sorted[key] = sortObject(entryValue as JsonValue);
    }
    return sorted;
  }
  return value;
}

function sortById<T extends { id: string }>(items: T[]): T[] {
  return [...items].sort((a, b) => a.id.localeCompare(b.id));
}

function sortLogs<T extends { request_id: string; created_at?: string }>(items: T[]): T[] {
  return [...items].sort((a, b) => {
    if (a.created_at && b.created_at) {
      const byTime = a.created_at.localeCompare(b.created_at);
      if (byTime !== 0) {
        return byTime;
      }
    }
    return a.request_id.localeCompare(b.request_id);
  });
}

function toCanonicalJson(value: unknown): string {
  const jsonSafe = JSON.parse(JSON.stringify(value)) as JsonValue;
  return JSON.stringify(sortObject(jsonSafe));
}

function runFluxctl(adminUrl: string, args: string[]): JsonValue {
  const proc = Bun.spawnSync(
    ['cargo', 'run', '-q', '-p', 'fluxctl', '--', '--admin-url', adminUrl, ...args],
    {
      stdout: 'pipe',
      stderr: 'pipe',
    },
  );
  if (proc.exitCode !== 0) {
    const stderr = proc.stderr.toString();
    throw new Error(`fluxctl ${args.join(' ')} failed: ${stderr}`);
  }
  const stdout = proc.stdout.toString().trim();
  return JSON.parse(stdout) as JsonValue;
}

async function main() {
  const adminUrl = process.argv[2];
  if (!adminUrl) {
    throw new Error('usage: bun scripts/e2e/validate_cli_desktop_consistency.ts <admin-url>');
  }

  const api = createAdminApi(adminUrl);
  const [desktopProviders, desktopGateways, desktopLogsPage] = await Promise.all([
    api.listProviders(),
    api.listGateways(),
    api.listLogs({ limit: 50 }),
  ]);

  const cliProviders = runFluxctl(adminUrl, ['provider', 'list']) as JsonValue[];
  const cliGateways = runFluxctl(adminUrl, ['gateway', 'list']) as JsonValue[];
  const cliLogsPage = runFluxctl(adminUrl, ['logs']) as { items?: JsonValue[] };

  const normalizedDesktop = {
    providers: sortById(desktopProviders),
    gateways: sortById(desktopGateways),
    logs: sortLogs(desktopLogsPage.items),
  };
  const normalizedCli = {
    providers: sortById(cliProviders as { id: string }[]),
    gateways: sortById(cliGateways as { id: string }[]),
    logs: sortLogs((cliLogsPage.items ?? []) as { request_id: string; created_at?: string }[]),
  };

  if (toCanonicalJson(normalizedDesktop.providers) !== toCanonicalJson(normalizedCli.providers)) {
    throw new Error(
      `providers mismatch\ncli=${toCanonicalJson(normalizedCli.providers)}\ndesktop=${toCanonicalJson(normalizedDesktop.providers)}`,
    );
  }
  if (toCanonicalJson(normalizedDesktop.gateways) !== toCanonicalJson(normalizedCli.gateways)) {
    throw new Error(
      `gateways mismatch\ncli=${toCanonicalJson(normalizedCli.gateways)}\ndesktop=${toCanonicalJson(normalizedDesktop.gateways)}`,
    );
  }
  if (toCanonicalJson(normalizedDesktop.logs) !== toCanonicalJson(normalizedCli.logs)) {
    throw new Error(`logs mismatch\ncli=${toCanonicalJson(normalizedCli.logs)}\ndesktop=${toCanonicalJson(normalizedDesktop.logs)}`);
  }

  console.log('cli-desktop consistency ok');
}

await main();
