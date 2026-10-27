import { readFile, writeFile, mkdtemp, cp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const key = process.env.WINDY_API_KEY;
if (!key?.trim()) throw new Error('Cadastre o segredo WINDY_API_KEY nas configurações Actions do repositório.');
const repository = process.env.GITHUB_REPOSITORY;
const sha = process.env.GITHUB_SHA;
const owner = process.env.GITHUB_REPOSITORY_OWNER;
if (!repository || !owner || !/^[a-f0-9]{40}$/i.test(sha ?? '')) throw new Error('Execute a publicação pelo workflow do GitHub.');

const temp = await mkdtemp(join(tmpdir(), 'nicky-windy-'));
try {
  const staging = join(temp, 'plugin');
  await cp(resolve('dist'), staging, { recursive: true });
  const manifestPath = join(staging, 'plugin.json');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  if (manifest.name !== 'windy-plugin-nicky' || manifest.private !== true) throw new Error('Manifesto do plugin privado inválido.');
  Object.assign(manifest, { repositoryName: repository, repositoryOwner: owner, commitSha: sha });
  await writeFile(manifestPath, JSON.stringify(manifest, null, 2));
  const archive = join(temp, 'plugin.tar');
  execFileSync('tar', ['-cf', archive, '-C', staging, '.'], { stdio: 'pipe' });
  const form = new FormData();
  form.append('plugin_archive', new Blob([await readFile(archive)], { type: 'application/x-tar' }), 'plugin.tar');
  const response = await fetch('https://node.windy.com/plugins/v1.0/upload', {
    method: 'POST', headers: { 'x-windy-api-key': key }, body: form,
    signal: AbortSignal.timeout(120000),
  });
  if (!response.ok) throw new Error(`Windy recusou a publicação (HTTP ${response.status}). Confira a chave Plugins e se a versão já foi publicada.`);
  const body = await response.text();
  const urls = [...new Set(body.match(/https:\/\/windy-plugins\.com\/[^\s"'<>\\]+/g) ?? [])];
  const selected = urls.find(url => url.includes('/windy-plugin-nicky/') && url.endsWith('/plugin.min.js'));
  const summary = selected
    ? `## Plugin Nicky publicado\n\nVersão: ${manifest.version}\n\nURL do plugin: ${selected}\n\nNo Windy, abra Menu → Install Windy Plugin e use a URL acima. Valide primeiro o botão Testar 5 cores.\n`
    : `## Publicação aceita pelo Windy\n\nVersão: ${manifest.version}\n\nO servidor não retornou uma URL reconhecida pelo script. É necessário conferir o endereço antes da instalação; não tente reenviar a mesma versão.\n`;
  await writeFile('publication.txt', summary);
  if (process.env.GITHUB_STEP_SUMMARY) await writeFile(process.env.GITHUB_STEP_SUMMARY, summary, { flag: 'a' });
  console.log(selected ? `Plugin publicado: ${selected}` : 'Envio aceito. Confira o resumo da execução para a próxima etapa.');
} finally {
  await rm(temp, { recursive: true, force: true });
}
