/**
 * Cria o arquivo de variaveis locais do app a partir do modelo.
 *
 * O databricks.yml nao guarda id de warehouse nem de Genie space -- eles sao
 * variaveis sem default. Quem as preenche e
 * .databricks/bundle/default/variable-overrides.json, que o .gitignore exclui.
 *
 * Node, e nao PowerShell, de proposito: este script roda via `npm run`, e no
 * Windows o npm executa pelo cmd.exe. Um .ps1 ali exigiria um prefixo que
 * quebra em outros sistemas; `node` funciona nos tres.
 *
 * Nao sobrescreve o que ja existe. `npm run configurar -- --force` sobrescreve.
 */
import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const modelo = join(raiz, 'variable-overrides.exemplo.json');
const pasta = join(raiz, '.databricks', 'bundle', 'default');
const destino = join(pasta, 'variable-overrides.json');
const forcar = process.argv.includes('--force');

if (!existsSync(modelo)) {
  console.error(`Modelo nao encontrado: ${modelo}`);
  process.exit(1);
}

if (existsSync(destino) && !forcar) {
  console.log(`ja existe, mantido: ${destino}`);
  console.log('use `npm run configurar -- --force` para sobrescrever.');
  process.exit(0);
}

mkdirSync(pasta, { recursive: true });
copyFileSync(modelo, destino);
console.log(`criado: ${destino}`);
console.log('');
console.log('Preencha sql_warehouse_id e genie_space_id. Para descobrir:');
console.log('  databricks warehouses list --profile <perfil>');
console.log('  cd ../rotaperfumes && databricks bundle summary --profile <perfil>');
