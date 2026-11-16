import { test, before, after, beforeEach } from 'node:test';
import fs from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, addDoc, deleteDoc, collection, getDocs,
  query, where, serverTimestamp, Timestamp,
} from 'firebase/firestore';

let env;

const pad = (n) => String(n).padStart(2, '0');
const utcToday = () => {
  const d = new Date();
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
};

const baseUser = (over = {}) => ({
  name: 'A', email: 'a@x.com', role: 'user',
  wallet: { stardust: 500 },
  inventory: ['skin_classic', 'bg_void'],
  ...over,
});

const item = (price, over = {}) => ({ price, type: 'skin', rarity: 'common', active: true, ...over });

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-astrum',
    firestore: { rules: fs.readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080) },
  });
});
after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), baseUser());
    await setDoc(doc(db, 'users/bob'), baseUser({ name: 'B', email: 'b@x.com' }));
    await setDoc(doc(db, 'users/root'), baseUser({ role: 'admin' }));
    // catalogo: itens pagos a 100, mais um gratuito e um inativo
    for (const id of ['a', 'b', 'skin_x']) {
      await setDoc(doc(db, `shop_items/${id}`), item(100));
    }
    await setDoc(doc(db, 'shop_items/bg_y'), item(100, { type: 'background' }));
    await setDoc(doc(db, 'shop_items/pfp_zodiac_leao'), item(0, { type: 'profilePicture' }));
    await setDoc(doc(db, 'shop_items/pfp_zodiac_off'), item(0, { type: 'profilePicture', active: false }));
    await setDoc(doc(db, 'shop_items/free'), item(0));
    await setDoc(doc(db, 'shop_items/off'), item(100, { active: false }));
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();

test('dono le o proprio perfil; outro usuario nao', async () => {
  await assertSucceeds(getDoc(doc(as('alice'), 'users/alice')));
  await assertFails(getDoc(doc(as('alice'), 'users/bob')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/alice')));
});

test('admin le qualquer usuario; usuario comum nao consulta por email', async () => {
  await assertSucceeds(getDoc(doc(as('root'), 'users/alice')));
  await assertSucceeds(getDocs(collection(as('root'), 'users')));
  await assertFails(getDocs(query(collection(as('alice'), 'users'), where('email', '==', 'b@x.com'))));
});

test('create: role admin negado; wallet diferente negada; valido ok', async () => {
  const db = as('carol');
  await assertFails(setDoc(doc(db, 'users/carol'), baseUser({ role: 'admin' })));
  await assertFails(setDoc(doc(db, 'users/carol'), baseUser({ wallet: { stardust: 99999 } })));
  await assertFails(setDoc(doc(as('alice'), 'users/carol'), baseUser()));
  await assertSucceeds(setDoc(doc(db, 'users/carol'), baseUser()));
});

test('update: mudar role negado', async () => {
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { role: 'admin' }));
});

test('update: reescrever wallet inteiro como mapa negado', async () => {
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { wallet: { stardust: 9999 } }));
});

test('update: aumentar stardust fora de check-in negado', async () => {
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { 'wallet.stardust': 100000 }));
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { 'wallet.stardust': 525 }));
});

test('update: inventario sem compra negado; campos comuns ok', async () => {
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { inventory: ['skin_classic', 'bg_void', 'x'] }));
  await assertSucceeds(updateDoc(doc(as('alice'), 'users/alice'), { 'preferences.showSign': false, 'equipped.skin': 'skin_classic' }));
});

test('check-in: +25 com data de hoje ok; repetir negado; +26 negado', async () => {
  const ref = doc(as('alice'), 'users/alice');
  await assertFails(updateDoc(ref, { dailyCheckIn: utcToday(), 'wallet.stardust': 526 }));
  await assertSucceeds(updateDoc(ref, { dailyCheckIn: utcToday(), 'wallet.stardust': 525 }));
  await assertFails(updateDoc(ref, { dailyCheckIn: utcToday(), 'wallet.stardust': 550 }));
  await assertFails(updateDoc(ref, { dailyCheckIn: '2000-01-01', 'wallet.stardust': 550 }));
});

test('check-in: resetar dailyCheckIn sem saldo negado', async () => {
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { dailyCheckIn: '2000-01-01' }));
});

test('compra: diminui e +1 item ok; saldo negativo, 2 itens ou sem item negados', async () => {
  const ref = doc(as('alice'), 'users/alice');
  await assertFails(updateDoc(ref, { 'wallet.stardust': -1, inventory: ['skin_classic', 'bg_void', 'a'] }));
  await assertFails(updateDoc(ref, { 'wallet.stardust': 400, inventory: ['skin_classic', 'bg_void', 'a', 'b'] }));
  await assertFails(updateDoc(ref, { 'wallet.stardust': 400 }));
  await assertFails(updateDoc(ref, { 'wallet.stardust': 400, inventory: ['a', 'b', 'c'] }));
  await assertSucceeds(updateDoc(ref, { 'wallet.stardust': 400, inventory: ['skin_classic', 'bg_void', 'a'] }));
});

test('delete do perfil: dono ok; outro usuario, admin e anonimo negados', async () => {
  const ref = (db) => doc(db, 'users/alice');
  await assertFails(deleteDoc(ref(as('bob'))));
  await assertFails(deleteDoc(ref(as('root'))));
  await assertFails(deleteDoc(ref(env.unauthenticatedContext().firestore())));
  await assertSucceeds(deleteDoc(ref(as('alice'))));
  let existe = true;
  await env.withSecurityRulesDisabled(async (ctx) => { existe = (await getDoc(doc(ctx.firestore(), 'users/alice'))).exists(); });
  if (existe) throw new Error('perfil nao foi apagado');
});

test('events/friends: create exige o perfil; update e delete continuam do dono', async () => {
  // sem perfil: negado
  await env.withSecurityRulesDisabled(async (ctx) => { await deleteDoc(doc(ctx.firestore(), 'users/alice')); });
  await assertFails(addDoc(collection(as('alice'), 'users/alice/events'), { title: 't' }));
  await assertFails(setDoc(doc(as('alice'), 'users/alice/friends/bob'), { name: 'B' }));
  // com perfil: permitido
  await env.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), 'users/alice'), baseUser()); });
  await assertSucceeds(addDoc(collection(as('alice'), 'users/alice/events'), { title: 't' }));
  await assertSucceeds(setDoc(doc(as('alice'), 'users/alice/friends/bob'), { name: 'B' }));
  // update e delete sem perfil continuam permitidos ao dono (cascata da exclusao)
  await env.withSecurityRulesDisabled(async (ctx) => { await deleteDoc(doc(ctx.firestore(), 'users/alice')); });
  await assertSucceeds(updateDoc(doc(as('alice'), 'users/alice/friends/bob'), { name: 'B2' }));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'users/alice/friends/bob')));
  // outro usuario continua negado
  await assertFails(setDoc(doc(as('bob'), 'users/alice/friends/x'), { name: 'X' }));
});

test('subcolecoes: so o dono', async () => {
  await assertSucceeds(addDoc(collection(as('alice'), 'users/alice/events'), { title: 't' }));
  await assertFails(addDoc(collection(as('bob'), 'users/alice/events'), { title: 't' }));
  await assertFails(getDocs(collection(as('bob'), 'users/alice/friends')));
  await assertFails(setDoc(doc(as('alice'), 'users/alice/outra/x'), { a: 1 }));
});

test('notificacao: amigo + intencao fixa + nome real ok; forjar, texto livre e sem amizade negados; outro nao le', async () => {
  const n = (from, over = {}) => ({ type: 'intention', intentionId: 'luz', intentionLabel: 'Luz', fromName: 'A', fromUid: from, read: false, createdAt: serverTimestamp(), ...over });
  const col = (db) => collection(db, 'users/bob/notifications');
  // sem amizade: negado, mesmo com campos coerentes
  await assertFails(addDoc(col(as('alice')), n('alice')));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/alice/friends/bob'), { name: 'B', email: 'b@x.com', zodiacSign: 'Leo' });
  });
  await assertSucceeds(addDoc(col(as('alice')), n('alice')));
  await assertFails(addDoc(col(as('alice')), n('carol')));
  await assertFails(addDoc(col(as('alice')), n('alice', { fromName: 'Presidente do banco' })));
  await assertFails(addDoc(col(as('alice')), n('alice', { intentionLabel: 'clique em x.com' })));
  await assertFails(addDoc(col(as('alice')), n('alice', { intentionId: 'livre', intentionLabel: 'livre' })));
  await assertFails(getDocs(col(as('alice'))));
});

test('notificacao: fromName livre sem amizade negado', async () => {
  const n = { type: 'intention', intentionId: 'luz', intentionLabel: 'Luz', fromName: 'Qualquer Coisa', fromUid: 'alice', read: false, createdAt: serverTimestamp() };
  await assertFails(addDoc(collection(as('alice'), 'users/bob/notifications'), n));
});

test('perfil: campo extra negado; equipar item nao possuido negado; possuido ok', async () => {
  const ref = doc(as('alice'), 'users/alice');
  await assertFails(updateDoc(ref, { campoExtra: 'x' }));
  await assertFails(updateDoc(ref, { 'equipped.skin': 'skin_dourada' }));
  await assertFails(updateDoc(ref, { 'equipped.profilePicture': 'pfp_nao_possuida' }));
  await assertFails(updateDoc(ref, { 'equipped.outro': 'skin_classic' }));
  await assertFails(updateDoc(ref, { name: 'x'.repeat(101) }));
  await assertSucceeds(updateDoc(ref, { 'equipped.skin': 'skin_classic' }));
  await assertSucceeds(updateDoc(ref, { 'equipped.background': 'bg_void', 'equipped.profilePicture': null }));
});

test('compra com equipar: equipa o item recem comprado; item nao comprado negado', async () => {
  const ref = doc(as('alice'), 'users/alice');
  await assertSucceeds(updateDoc(ref, { 'wallet.stardust': 400, inventory: ['skin_classic', 'bg_void', 'skin_x'], 'equipped.skin': 'skin_x' }));
  await assertFails(updateDoc(ref, { 'wallet.stardust': 300, inventory: ['skin_classic', 'bg_void', 'skin_x', 'bg_y'], 'equipped.background': 'bg_z' }));
});

test('criar perfil com campo extra ou equipped nao possuido negado', async () => {
  const db = as('carol');
  await assertFails(setDoc(doc(db, 'users/carol'), baseUser({ extra: 1 })));
  await assertFails(setDoc(doc(db, 'users/carol'), baseUser({ equipped: { skin: 'skin_x' } })));
  await assertSucceeds(setDoc(doc(db, 'users/carol'), baseUser({
    equipped: { skin: 'skin_classic', background: 'bg_void', profilePicture: null },
    preferences: { notifications: true, publicProfile: true, showSign: true },
    astrologyData: { sun: 'Leo', moon: null, ascendant: null },
  })));
});

test('analytics: create proprio ok; userId alheio negado; leitura negada; admin le', async () => {
  const ev = (u) => ({ eventName: 'x', userId: u, createdAt: serverTimestamp() });
  await assertSucceeds(addDoc(collection(as('alice'), 'analytics_events'), ev('alice')));
  await assertFails(addDoc(collection(as('alice'), 'analytics_events'), ev('bob')));
  await assertFails(addDoc(collection(as('alice'), 'analytics_events'), { ...ev('alice'), extra: 1 }));
  await assertSucceeds(addDoc(collection(env.unauthenticatedContext().firestore(), 'analytics_events'), ev('anonymous')));
  await assertFails(getDocs(collection(as('alice'), 'analytics_events')));
  await assertSucceeds(getDocs(collection(as('root'), 'analytics_events')));
});

test('caminho desconhecido negado', async () => {
  await assertFails(setDoc(doc(as('alice'), 'qualquer/x'), { a: 1 }));
  await assertFails(getDoc(doc(as('root'), 'qualquer/x')));
});

// ---- conversas
import { writeBatch, increment } from 'firebase/firestore';
const conv = (n, over = {}) => ({
  title: 'oi', createdAt: Timestamp.now(), updatedAt: Timestamp.now(), messageCount: n, schemaVersion: 1, ...over,
});
const msg = (over = {}) => ({ role: 'user', text: 'oi', createdAt: Timestamp.now(), ...over });

test('conversas: dono cria; outro nao; titulo >80 negado', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'users/alice/conversations/c1'), conv(0)));
  await assertFails(setDoc(doc(as('bob'), 'users/alice/conversations/c2'), conv(0)));
  await assertFails(setDoc(doc(as('alice'), 'users/alice/conversations/c3'), conv(0, { title: 'x'.repeat(81) })));
});

test('mensagens: batch valido ok; 10001 chars, role invalido, update, 501a, sem conversa negados', async () => {
  const db = as('alice');
  await setDoc(doc(db, 'users/alice/conversations/c1'), conv(0));
  const send = async (id, m, count) => {
    const b = writeBatch(db);
    b.set(doc(db, `users/alice/conversations/c1/messages/${id}`), m);
    b.update(doc(db, 'users/alice/conversations/c1'), { messageCount: count, updatedAt: Timestamp.now() });
    return b.commit();
  };
  await assertSucceeds(send('m1', msg(), 1));
  await assertFails(send('m2', msg({ text: 'x'.repeat(10001) }), 2));
  await assertFails(send('m3', msg({ role: 'admin' }), 2));
  await assertFails(updateDoc(doc(db, 'users/alice/conversations/c1/messages/m1'), { text: 'novo' }));
  await assertFails(send('m4', msg(), 501));
  await assertFails(setDoc(doc(db, 'users/alice/conversations/zzz/messages/m1'), msg()));
  await assertFails(getDoc(doc(as('bob'), 'users/alice/conversations/c1/messages/m1')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/conversations/c1/messages/m1')));
});

test('mensagens: sem incrementar messageCount negado; incremento de 1 ok; salto de 2 negado; contador nao diminui', async () => {
  const db = as('alice');
  await setDoc(doc(db, 'users/alice/conversations/c1'), conv(0));
  const send = (id, count) => {
    const b = writeBatch(db);
    b.set(doc(db, `users/alice/conversations/c1/messages/${id}`), msg());
    if (count !== null) b.update(doc(db, 'users/alice/conversations/c1'), { messageCount: count, updatedAt: Timestamp.now() });
    return b.commit();
  };
  await assertFails(send('m1', null)); // mensagem sem tocar na conversa
  await assertFails(send('m1', 0)); // contador igual
  await assertFails(send('m1', 2)); // salto de 2
  await assertSucceeds(send('m1', 1));
  await assertFails(updateDoc(doc(db, 'users/alice/conversations/c1'), { messageCount: 0 })); // diminuir
  await assertFails(updateDoc(doc(db, 'users/alice/conversations/c1'), { messageCount: 3 })); // subir 2
  await assertSucceeds(send('m2', 2));
});

test('mensagens: conversa criada no mesmo batch com contador 1 ok; contador 2 negado', async () => {
  const db = as('alice');
  const make = (count) => {
    const b = writeBatch(db);
    b.set(doc(db, 'users/alice/conversations/n1'), conv(count));
    b.set(doc(db, 'users/alice/conversations/n1/messages/m1'), msg());
    return b.commit();
  };
  await assertFails(make(0));
  await assertFails(make(2));
  await assertSucceeds(make(1));
});

// ---- conversas: increment(1), limites, titulo com emoji, imutabilidade, isolamento (etapa 10, passo 1)
const sendInc = (db, convId, id, m, by = 1) => {
  const b = writeBatch(db);
  b.set(doc(db, `users/alice/conversations/${convId}/messages/${id}`), m);
  b.update(doc(db, `users/alice/conversations/${convId}`), { messageCount: increment(by), updatedAt: Timestamp.now() });
  return b.commit();
};
const seedConv = (id, n, uid = 'alice') =>
  env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `users/${uid}/conversations/${id}`), conv(n)));

test('conversas: messageCount via increment(1) ok; increment(2), increment(0) e increment(-1) negados', async () => {
  const db = as('alice');
  await seedConv('c1', 0);
  await assertFails(sendInc(db, 'c1', 'm0001', msg(), 2));
  await assertFails(sendInc(db, 'c1', 'm0001', msg(), 0));
  await assertSucceeds(sendInc(db, 'c1', 'm0001', msg()));
  await assertSucceeds(sendInc(db, 'c1', 'm0002', msg({ role: 'model' })));
  await assertFails(sendInc(db, 'c1', 'm0003', msg(), -1));
});

test('conversas: 1a mensagem cria a conversa com contador 1 e a mensagem no mesmo batch; depois increment ok', async () => {
  const db = as('alice');
  const b = writeBatch(db);
  b.set(doc(db, 'users/alice/conversations/n1'), conv(1, { title: 'primeira pergunta' }));
  b.set(doc(db, 'users/alice/conversations/n1/messages/m0001'), msg());
  await assertSucceeds(b.commit());
  await assertSucceeds(sendInc(db, 'n1', 'm0002', msg({ role: 'model' })));
});

test('conversas: 500a mensagem ok via increment; 501a negada', async () => {
  const db = as('alice');
  await seedConv('c1', 499);
  await assertSucceeds(sendInc(db, 'c1', 'm0500', msg()));
  await assertFails(sendInc(db, 'c1', 'm0501', msg()));
  await assertFails(updateDoc(doc(db, 'users/alice/conversations/c1'), { messageCount: 501 }));
});

test('conversas: titulo de 80 unidades UTF-16 com emoji ok; 81 e vazio negados', async () => {
  const db = as('alice');
  const emoji = '\u{1F52E}'; // 2 unidades UTF-16
  const t80 = 'a'.repeat(78) + emoji; // 80 unidades
  if (t80.length !== 80) throw new Error(`titulo de teste com ${t80.length} unidades`);
  await assertSucceeds(setDoc(doc(db, 'users/alice/conversations/e1'), conv(0, { title: t80 })));
  await assertSucceeds(setDoc(doc(db, 'users/alice/conversations/e2'), conv(0, { title: emoji.repeat(40) })));
  await assertFails(setDoc(doc(db, 'users/alice/conversations/e3'), conv(0, { title: 'a'.repeat(81) })));
  await assertFails(setDoc(doc(db, 'users/alice/conversations/e4'), conv(0, { title: '' })));
});

test('mensagens: imutaveis (reenviar o mesmo id, set e update negados)', async () => {
  const db = as('alice');
  await seedConv('c1', 0);
  await assertSucceeds(sendInc(db, 'c1', 'm0001', msg({ text: 'original' })));
  // reenviar o mesmo id vira update: negado, mesmo com o contador subindo 1
  await assertFails(sendInc(db, 'c1', 'm0001', msg({ text: 'trocada' })));
  await assertFails(setDoc(doc(db, 'users/alice/conversations/c1/messages/m0001'), msg({ text: 'trocada' })));
  await assertFails(updateDoc(doc(db, 'users/alice/conversations/c1/messages/m0001'), { text: 'trocada' }));
  const snap = await getDoc(doc(db, 'users/alice/conversations/c1/messages/m0001'));
  if (snap.data().text !== 'original') throw new Error('mensagem foi alterada');
});

test('conversas: outro uid nao le, cria, atualiza, apaga nem envia mensagem', async () => {
  await seedConv('c1', 1);
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'users/alice/conversations/c1/messages/m0001'), msg()));
  const bob = as('bob');
  await assertFails(getDoc(doc(bob, 'users/alice/conversations/c1')));
  await assertFails(getDocs(collection(bob, 'users/alice/conversations')));
  await assertFails(getDoc(doc(bob, 'users/alice/conversations/c1/messages/m0001')));
  await assertFails(setDoc(doc(bob, 'users/alice/conversations/c2'), conv(0)));
  await assertFails(updateDoc(doc(bob, 'users/alice/conversations/c1'), { updatedAt: Timestamp.now() }));
  await assertFails(deleteDoc(doc(bob, 'users/alice/conversations/c1')));
  await assertFails(deleteDoc(doc(bob, 'users/alice/conversations/c1/messages/m0001')));
  await assertFails(sendInc(bob, 'c1', 'm0002', msg()));
  // o dono continua lendo
  await assertSucceeds(getDoc(doc(as('alice'), 'users/alice/conversations/c1')));
});

// ---- conversas: exclusao, createdAt, colisao de isNew, alheio, caracterizacao (correcoes da revisao, etapa 10)
test('conversas: dono apaga mensagem e depois a conversa (cascata do cliente)', async () => {
  const db = as('alice');
  await seedConv('c1', 1);
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'users/alice/conversations/c1/messages/m0001'), msg()));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/conversations/c1/messages/m0001')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/conversations/c1')));
  const snap = await getDoc(doc(db, 'users/alice/conversations/c1'));
  if (snap.exists()) throw new Error('conversa nao foi apagada');
});

test('conversas: update que altera createdAt negado (imutavel)', async () => {
  const db = as('alice');
  await seedConv('c1', 0);
  await assertFails(updateDoc(doc(db, 'users/alice/conversations/c1'), {
    createdAt: Timestamp.fromMillis(1000), updatedAt: Timestamp.now(),
  }));
  // mesmo junto de um incremento valido
  await assertFails(updateDoc(doc(db, 'users/alice/conversations/c1'), {
    createdAt: Timestamp.fromMillis(1000), messageCount: increment(1), updatedAt: Timestamp.now(),
  }));
});

test('conversas: set sobre conversa existente (colisao de isNew) negado, com ou sem mensagem', async () => {
  const db = as('alice');
  await seedConv('c1', 3); // ja existe, createdAt dela
  // set vira update: createdAt novo (!= existente) e contador 1 (diminui) violam a regra
  await assertFails(setDoc(doc(db, 'users/alice/conversations/c1'), conv(1)));
  const b = writeBatch(db);
  b.set(doc(db, 'users/alice/conversations/c1'), conv(1));
  b.set(doc(db, 'users/alice/conversations/c1/messages/m0001'), msg());
  await assertFails(b.commit());
  // conversa preservada
  const snap = await getDoc(doc(db, 'users/alice/conversations/c1'));
  if (snap.data().messageCount !== 3) throw new Error('conversa foi alterada');
});

test('conversas: colisao de isNew com createdAt igual mas contador 3->1 negada (regra do contador isolada)', async () => {
  const db = as('alice');
  await seedConv('c1', 3);
  const ref = doc(db, 'users/alice/conversations/c1');
  const existing = (await getDoc(ref)).data();
  // createdAt identico ao existente: so o contador (3 -> 1, diminui) viola a regra
  await assertFails(setDoc(ref, conv(1, { createdAt: existing.createdAt })));
  const snap = await getDoc(ref);
  if (snap.data().messageCount !== 3) throw new Error('conversa foi alterada');
});

test('conversas: update de conversa alheia com increment negado', async () => {
  await seedConv('c1', 0);
  await assertFails(updateDoc(doc(as('bob'), 'users/alice/conversations/c1'), {
    messageCount: increment(1), updatedAt: Timestamp.now(),
  }));
  const snap = await getDoc(doc(as('alice'), 'users/alice/conversations/c1'));
  if (snap.data().messageCount !== 0) throw new Error('contador alheio foi alterado');
});

// CARACTERIZACAO (nao e um requisito): a regra da conversa aceita um update do
// dono com messageCount +1 SEM mensagem no batch (a regra da mensagem exige o
// contador, mas a da conversa nao exige a mensagem). E autoprejuizo: so o dono
// infla o proprio contador (ate 500, ficando sem espaco para mensagens reais)
// e a migracao detecta a divergencia (confere por CONTAGEM de mensagens, nao por ids). Registrado como risco
// aceito no step10-chat-sync.md; se a regra mudar, este teste deve ser revisto.
test('caracterizacao: update do dono com +1 sem mensagem e aceito (autoprejuizo)', async () => {
  const db = as('alice');
  await seedConv('c1', 0);
  await assertSucceeds(updateDoc(doc(db, 'users/alice/conversations/c1'), {
    messageCount: increment(1), updatedAt: Timestamp.now(),
  }));
  const snap = await getDoc(doc(db, 'users/alice/conversations/c1'));
  if (snap.data().messageCount !== 1) throw new Error('contador nao subiu');
});

// ---- catalogo da loja (shop_items)
test('compra: saldo debitado igual ao preco do catalogo ok; diferente negado', async () => {
  const ref = doc(as('alice'), 'users/alice');
  const inv = ['skin_classic', 'bg_void', 'a'];
  await assertFails(updateDoc(ref, { 'wallet.stardust': 499, inventory: inv })); // debitou 1
  await assertFails(updateDoc(ref, { 'wallet.stardust': 300, inventory: inv })); // debitou 200
  await assertFails(updateDoc(ref, { 'wallet.stardust': 500, inventory: inv })); // nao debitou
  await assertSucceeds(updateDoc(ref, { 'wallet.stardust': 400, inventory: inv }));
});

test('compra: item inativo, sem doc no catalogo ou ja possuido (duplicado) negados', async () => {
  const ref = doc(as('alice'), 'users/alice');
  await assertFails(updateDoc(ref, { 'wallet.stardust': 400, inventory: ['skin_classic', 'bg_void', 'off'] }));
  await assertFails(updateDoc(ref, { 'wallet.stardust': 400, inventory: ['skin_classic', 'bg_void', 'sem_doc'] }));
  await assertFails(updateDoc(ref, { 'wallet.stardust': 400, inventory: ['skin_classic', 'bg_void', 'skin_classic'] }));
});

test('item de preco zero: com doc no catalogo permitido e saldo igual; saldo menor negado', async () => {
  const ref = doc(as('alice'), 'users/alice');
  await assertFails(updateDoc(ref, { 'wallet.stardust': 400, inventory: ['skin_classic', 'bg_void', 'free'] }));
  await assertSucceeds(updateDoc(ref, { inventory: ['skin_classic', 'bg_void', 'free'] }));
});

test('item de preco zero sem doc no catalogo negado (e inativo tambem)', async () => {
  const ref = doc(as('alice'), 'users/alice');
  await assertFails(updateDoc(ref, { inventory: ['skin_classic', 'bg_void', 'pfp_gratis'] }));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'shop_items/free_off'), item(0, { active: false }));
  });
  await assertFails(updateDoc(ref, { inventory: ['skin_classic', 'bg_void', 'free_off'] }));
});

test('inventario: limite de 500 itens continua valendo', async () => {
  const big = Array.from({ length: 500 }, (_, i) => `i${i}`);
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/alice'), baseUser({ inventory: big }));
  });
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { inventory: [...big, 'free'] }));
});

test('shop_items: logado le; anonimo nao; usuario comum nao escreve; admin escreve', async () => {
  await assertSucceeds(getDoc(doc(as('alice'), 'shop_items/a')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'shop_items/a')));
  await assertFails(setDoc(doc(as('alice'), 'shop_items/novo'), item(1)));
  await assertFails(updateDoc(doc(as('alice'), 'shop_items/a'), { price: 1 }));
  await assertFails(deleteDoc(doc(as('alice'), 'shop_items/a')));
  await assertSucceeds(setDoc(doc(as('root'), 'shop_items/novo'), item(250)));
  await assertSucceeds(updateDoc(doc(as('root'), 'shop_items/a'), { price: 150 }));
});

test('shop_items: admin com dados invalidos negado', async () => {
  const db = as('root');
  await assertFails(setDoc(doc(db, 'shop_items/n1'), item(-1)));
  await assertFails(setDoc(doc(db, 'shop_items/n2'), item(1.5)));
  await assertFails(setDoc(doc(db, 'shop_items/n3'), item(1, { type: 'arma' })));
  await assertFails(setDoc(doc(db, 'shop_items/n4'), item(1, { active: 'sim' })));
  await assertFails(setDoc(doc(db, 'shop_items/n5'), item(1, { extra: 1 })));
});

// ---- brechas de inventario e catalogo
test('create: inventario com item extra alem do padrao negado; duplicata negada', async () => {
  const db = as('carol');
  await assertFails(setDoc(doc(db, 'users/carol'), baseUser({ inventory: ['skin_classic', 'bg_void', 'a'] })));
  await assertFails(setDoc(doc(db, 'users/carol'), baseUser({ inventory: ['skin_classic', 'bg_void', 'skin_classic'] })));
  await assertFails(setDoc(doc(db, 'users/carol'), baseUser({ inventory: ['skin_classic', 'bg_void', 'pfp_zodiac_leao', 'a'] })));
  await assertFails(setDoc(doc(db, 'users/carol'), baseUser({ inventory: ['skin_classic', 'bg_void', 'pfp_zodiac_off'] })));
});

test('create: pfp zodiacal padrao valido permitido (e equipado)', async () => {
  const db = as('carol');
  await assertSucceeds(setDoc(doc(db, 'users/carol'), baseUser({
    inventory: ['skin_classic', 'bg_void', 'pfp_zodiac_leao'],
    equipped: { skin: 'skin_classic', background: 'bg_void', profilePicture: 'pfp_zodiac_leao' },
  })));
});

test('compra de item gratuito trocando duplicata por item livre negada', async () => {
  const ref = doc(as('alice'), 'users/alice');
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/alice'), baseUser({ inventory: ['skin_classic', 'bg_void', 'a'] }));
  });
  // troca 'a' (pago) por 'free' e acrescenta 'a' de novo: tamanho +1, hasAll falharia so se checasse ordem
  await assertFails(updateDoc(ref, { inventory: ['skin_classic', 'bg_void', 'free', 'free'] }));
  await assertFails(updateDoc(ref, { inventory: ['skin_classic', 'bg_void', 'free', 'a'] }));
  await assertFails(updateDoc(ref, { inventory: ['skin_classic', 'free', 'a', 'free'] }));
  await assertSucceeds(updateDoc(ref, { inventory: ['skin_classic', 'bg_void', 'a', 'free'] }));
});

test('equipar background no campo skin (e vice-versa) negado', async () => {
  const ref = doc(as('alice'), 'users/alice');
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/alice'), baseUser({ inventory: ['skin_classic', 'bg_void', 'skin_x', 'bg_y'] }));
  });
  await assertFails(updateDoc(ref, { 'equipped.skin': 'bg_y' }));
  await assertFails(updateDoc(ref, { 'equipped.background': 'skin_x' }));
  await assertFails(updateDoc(ref, { 'equipped.profilePicture': 'skin_x' }));
  await assertSucceeds(updateDoc(ref, { 'equipped.skin': 'skin_x', 'equipped.background': 'bg_y' }));
});

// Nota: a regra de shop_items NAO distingue "publicar catalogo" de "editar
// preco": o admin pode alterar price de item existente (teste acima). A
// protecao contra sobrescrever price/active e feita so no cliente (merge no
// botao Publicar catalogo); nao ha teste de regra para isso.

// ---- perfil publico (publicProfiles)
const HASH = 'a'.repeat(64);
const pub = (over = {}) => ({ name: 'A', avatar: 'pfp_leo', emailHash: HASH, ...over });

test('publicProfiles: logado le de outro; anonimo nao; consulta por emailHash ok', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'publicProfiles/bob'), pub({ name: 'B' }));
  });
  await assertSucceeds(getDoc(doc(as('alice'), 'publicProfiles/bob')));
  await assertSucceeds(getDocs(query(collection(as('alice'), 'publicProfiles'), where('emailHash', '==', HASH))));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'publicProfiles/bob')));
});

test('publicProfiles: dono cria e atualiza; escrever o de outro negado', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'publicProfiles/alice'), pub()));
  await assertSucceeds(setDoc(doc(as('alice'), 'publicProfiles/alice'), pub({ avatar: '' })));
  await assertSucceeds(updateDoc(doc(as('alice'), 'publicProfiles/alice'), { name: 'Novo' }));
  await assertFails(setDoc(doc(as('alice'), 'publicProfiles/bob'), pub()));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), 'publicProfiles/alice'), pub()));
});

test('publicProfiles: campo extra (email), hash de tamanho errado ou nao hex, nome invalido negados', async () => {
  const ref = doc(as('alice'), 'publicProfiles/alice');
  await assertFails(setDoc(ref, pub({ email: 'a@x.com' })));
  await assertFails(setDoc(ref, pub({ emailHash: 'a'.repeat(63) })));
  await assertFails(setDoc(ref, pub({ emailHash: 'a'.repeat(65) })));
  await assertFails(setDoc(ref, pub({ emailHash: 'A'.repeat(64) })));
  await assertFails(setDoc(ref, pub({ emailHash: 'g'.repeat(64) })));
  await assertFails(setDoc(ref, pub({ name: '' })));
  await assertFails(setDoc(ref, pub({ name: 'x'.repeat(101) })));
  await assertFails(setDoc(ref, { name: 'A', emailHash: HASH })); // sem avatar
});

test('publicProfiles: dono apaga e recria; outro uid, admin e anonimo negados', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'publicProfiles/alice'), pub()));
  await assertFails(deleteDoc(doc(as('bob'), 'publicProfiles/alice')));
  await assertFails(deleteDoc(doc(as('root'), 'publicProfiles/alice')));
  await assertFails(deleteDoc(doc(env.unauthenticatedContext().firestore(), 'publicProfiles/alice')));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'publicProfiles/alice')));
  const snap = await getDoc(doc(as('bob'), 'publicProfiles/alice'));
  if (snap.exists()) throw new Error('perfil publico nao foi apagado');
  await assertSucceeds(setDoc(doc(as('alice'), 'publicProfiles/alice'), pub()));
});

// ---- etapa 11: exclusao de conta (perfil ausente, intencoes enviadas, analytics)
const seedAlice = () => env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users/alice/conversations/c1'), conv(1));
  await setDoc(doc(db, 'users/alice/conversations/c1/messages/m0001'), msg());
  await setDoc(doc(db, 'users/alice/events/e1'), { title: 't' });
  await setDoc(doc(db, 'users/alice/friends/bob'), { name: 'B' });
  await setDoc(doc(db, 'users/alice/notifications/n1'), { type: 'intention', fromUid: 'bob', read: false });
});

test('perfil ausente: dono ainda le e apaga conversas, mensagens, eventos, amigos e notificacoes', async () => {
  await seedAlice();
  const db = as('alice');
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
  await assertSucceeds(getDocs(collection(db, 'users/alice/conversations')));
  await assertSucceeds(getDocs(collection(db, 'users/alice/conversations/c1/messages')));
  await assertSucceeds(getDocs(collection(db, 'users/alice/events')));
  await assertSucceeds(getDocs(collection(db, 'users/alice/friends')));
  await assertSucceeds(getDocs(collection(db, 'users/alice/notifications')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/conversations/c1/messages/m0001')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/conversations/c1')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/events/e1')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/friends/bob')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/notifications/n1')));
  // apagar de novo (documento inexistente) e idempotente
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
});

test('perfil ausente: conversa nova (com e sem mensagem no batch) negada; com perfil ok', async () => {
  const db = as('alice');
  await assertSucceeds(setDoc(doc(db, 'users/alice/conversations/ok'), conv(0)));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
  await assertFails(setDoc(doc(db, 'users/alice/conversations/n1'), conv(0)));
  const b = writeBatch(db);
  b.set(doc(db, 'users/alice/conversations/n2'), conv(1));
  b.set(doc(db, 'users/alice/conversations/n2/messages/m0001'), msg());
  await assertFails(b.commit());
});

test('intencao: destino sem perfil (conta excluida) negada; com perfil ok', async () => {
  const n = { type: 'intention', intentionId: 'luz', intentionLabel: 'Luz', fromName: 'A', fromUid: 'alice', read: false, createdAt: serverTimestamp() };
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice/friends/bob'), { name: 'B' });
    await setDoc(doc(db, 'users/alice/friends/ghost'), { name: 'G' });
  });
  await assertFails(addDoc(collection(as('alice'), 'users/ghost/notifications'), n));
  await assertSucceeds(addDoc(collection(as('alice'), 'users/bob/notifications'), n));
  await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'users/bob')));
  await assertFails(addDoc(collection(as('alice'), 'users/bob/notifications'), n));
});

// CARACTERIZACAO (nao e um requisito): com delete liberado, o dono apaga e
// recria o perfil; o saldo volta a 500 (o create exige exatamente 500) e o
// inventario volta ao padrao. Sem ganho acima do teto atual.
test('caracterizacao: apagar e recriar o perfil volta o saldo a 500 (nao acima)', async () => {
  const db = as('alice');
  await assertSucceeds(updateDoc(doc(db, 'users/alice'), { 'wallet.stardust': 400, inventory: ['skin_classic', 'bg_void', 'a'] }));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
  await assertFails(setDoc(doc(db, 'users/alice'), baseUser({ wallet: { stardust: 501 } })));
  await assertFails(setDoc(doc(db, 'users/alice'), baseUser({ inventory: ['skin_classic', 'bg_void', 'a'] })));
  await assertSucceeds(setDoc(doc(db, 'users/alice'), baseUser()));
  const snap = await getDoc(doc(db, 'users/alice'));
  if (snap.data().wallet.stardust !== 500) throw new Error('saldo nao voltou a 500');
  if (snap.data().inventory.length !== 2) throw new Error('inventario nao voltou ao padrao');
});

// ---- intencoes enviadas (collection group)
const seedSent = () => env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  const base = { type: 'intention', intentionId: 'luz', intentionLabel: 'Luz', fromName: 'A', read: false };
  await setDoc(doc(db, 'users/bob/notifications/s1'), { ...base, fromUid: 'alice', createdAt: Timestamp.now() });
  await setDoc(doc(db, 'users/root/notifications/s2'), { ...base, fromUid: 'alice', createdAt: Timestamp.now() });
  await setDoc(doc(db, 'users/bob/notifications/o1'), { ...base, fromUid: 'carol', createdAt: Timestamp.now() });
  await setDoc(doc(db, 'users/alice/notifications/r1'), { ...base, fromUid: 'bob', createdAt: Timestamp.now() });
});
const { collectionGroup } = await import('firebase/firestore');

test('intencoes enviadas: remetente consulta por fromUid e apaga as suas na caixa alheia', async () => {
  await seedSent();
  const db = as('alice');
  const snap = await assertSucceeds(getDocs(query(collectionGroup(db, 'notifications'), where('fromUid', '==', 'alice'))));
  if (snap.size !== 2) throw new Error(`esperava 2 intencoes enviadas, veio ${snap.size}`);
  for (const d of snap.docs) await assertSucceeds(deleteDoc(d.ref));
  const after = await getDocs(query(collectionGroup(as('alice'), 'notifications'), where('fromUid', '==', 'alice')));
  if (after.size !== 0) throw new Error('intencoes enviadas nao foram apagadas');
});

test('intencoes enviadas: fromUid de outro, consulta sem filtro e delete de terceiros negados', async () => {
  await seedSent();
  const db = as('alice');
  await assertFails(getDocs(query(collectionGroup(db, 'notifications'), where('fromUid', '==', 'carol'))));
  await assertFails(getDocs(collectionGroup(db, 'notifications')));
  await assertFails(getDocs(query(collectionGroup(db, 'notifications'), where('read', '==', false))));
  await assertFails(deleteDoc(doc(db, 'users/bob/notifications/o1')));
  await assertFails(getDoc(doc(db, 'users/bob/notifications/o1')));
  await assertFails(getDocs(query(collectionGroup(env.unauthenticatedContext().firestore(), 'notifications'), where('fromUid', '==', 'alice'))));
  // admin nao ganha delete de terceiros
  await assertFails(deleteDoc(doc(as('root'), 'users/bob/notifications/o1')));
  await assertFails(deleteDoc(doc(as('root'), 'users/bob/notifications/s1')));
});

test('intencoes enviadas: dono da caixa continua lendo e apagando as recebidas', async () => {
  await seedSent();
  const db = as('alice');
  await assertSucceeds(getDocs(collection(db, 'users/alice/notifications')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/notifications/r1')));
});

// ---- analytics_events: leitura e exclusao do proprio userId
test('analytics: dono consulta por userId e apaga os seus; sem filtro e userId alheio negados', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'analytics_events/a1'), { eventName: 'login', userId: 'alice', createdAt: Timestamp.now() });
    await setDoc(doc(db, 'analytics_events/a2'), { eventName: 'login', userId: 'alice', createdAt: Timestamp.now() });
    await setDoc(doc(db, 'analytics_events/b1'), { eventName: 'login', userId: 'bob', createdAt: Timestamp.now() });
    await setDoc(doc(db, 'analytics_events/x1'), { eventName: 'account_delete_completed', userId: 'anonymous', createdAt: Timestamp.now() });
  });
  const db = as('alice');
  const col = collection(db, 'analytics_events');
  await assertFails(getDocs(col));
  await assertFails(getDocs(query(col, where('userId', '==', 'bob'))));
  await assertFails(getDocs(query(col, where('userId', '==', 'anonymous'))));
  const mine = await assertSucceeds(getDocs(query(col, where('userId', '==', 'alice'))));
  if (mine.size !== 2) throw new Error(`esperava 2 eventos, veio ${mine.size}`);
  await assertFails(deleteDoc(doc(db, 'analytics_events/b1')));
  await assertFails(deleteDoc(doc(db, 'analytics_events/x1')));
  await assertFails(deleteDoc(doc(env.unauthenticatedContext().firestore(), 'analytics_events/a1')));
  await assertFails(updateDoc(doc(db, 'analytics_events/a1'), { eventName: 'outro' }));
  for (const d of mine.docs) await assertSucceeds(deleteDoc(d.ref));
  // admin continua lendo tudo, mas nao apaga eventos de terceiros
  const all = await assertSucceeds(getDocs(collection(as('root'), 'analytics_events')));
  if (all.size !== 2) throw new Error(`admin esperava 2 eventos restantes, veio ${all.size}`);
  await assertFails(deleteDoc(doc(as('root'), 'analytics_events/b1')));
});
