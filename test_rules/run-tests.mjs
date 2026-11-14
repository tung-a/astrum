// Executa os testes das regras no emulador do Firestore.
// A porta vem de FIRESTORE_EMULATOR_PORT (padrao 8080); firebase.json nao e alterado:
// geramos uma config temporaria com a porta escolhida.
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

const port = Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  console.error(`FIRESTORE_EMULATOR_PORT invalida: ${process.env.FIRESTORE_EMULATOR_PORT}`);
  process.exit(1);
}

// a config fica na raiz do projeto (as regras precisam estar dentro do diretorio do projeto)
const cfg = '../.firebase.rules-test.json';
fs.writeFileSync(cfg, JSON.stringify({
  firestore: { rules: 'firestore.rules', indexes: 'firestore.indexes.json' },
  emulators: { firestore: { port }, ui: { enabled: false } },
}));

let status = 1;
try {
  const r = spawnSync(
    `firebase --config ${cfg} emulators:exec --only firestore --project demo-astrum "node --test firestore.rules.test.mjs"`,
    [],
    { stdio: 'inherit', shell: true, env: { ...process.env, FIRESTORE_EMULATOR_PORT: String(port) } },
  );
  status = r.status ?? 1;
} finally {
  fs.rmSync(cfg, { force: true });
}
process.exit(status);
