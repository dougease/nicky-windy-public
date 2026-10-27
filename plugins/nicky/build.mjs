import { spawnSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
mkdirSync('dist', { recursive: true });
const result = spawnSync(process.execPath, ['node_modules/rollup/dist/bin/rollup', '-c'], {
  stdio: 'inherit', env: { ...process.env, SERVE: 'false' }
});
process.exit(result.status ?? 1);
