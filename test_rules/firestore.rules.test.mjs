import { test, before, after, beforeEach } from 'node:test';
import fs from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, addDoc, deleteDoc, collection, getDocs,
  query, where, limit, serverTimestamp, Timestamp,
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

// ---- helpers das amizades e do perfil publico (definidos no topo: os testes
// rodam enquanto o modulo ainda avalia)
const HASH = 'a'.repeat(64);
const pub = (over = {}) => ({ name: 'A', avatar: 'pfp_leo', emailHash: HASH, ...over });
const NAMES = { alice: 'A', bob: 'B', carol: 'C' };
const pidOf = (a, b) => (a < b ? `${a}_${b}` : `${b}_${a}`);
const reqDoc = (from, to, over = {}) => ({
  uids: [from, to].sort(),
  requesterUid: from,
  requesterName: NAMES[from] ?? 'X',
  status: 'pending',
  createdAt: serverTimestamp(),
  ...over,
});
const fref = (db, a, b) => doc(db, `friendships/${pidOf(a, b)}`);
const seedFriendUsers = () => env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users/carol'), baseUser({ name: 'C', email: 'c@x.com' }));
  for (const u of ['alice', 'bob', 'carol']) {
    await setDoc(doc(db, `publicProfiles/${u}`), pub({ name: NAMES[u] }));
  }
});
const seedFs = (a, b, over = {}) => env.withSecurityRulesDisabled((ctx) =>
  setDoc(fref(ctx.firestore(), a, b), {
    uids: [a, b].sort(), requesterUid: a, requesterName: NAMES[a] ?? 'X',
    status: 'pending', createdAt: Timestamp.now(), ...over,
  }));
const readFs = async (a, b) => {
  let data = null;
  await env.withSecurityRulesDisabled(async (ctx) => {
    const s = await getDoc(fref(ctx.firestore(), a, b));
    data = s.exists() ? s.data() : null;
  });
  return data;
};


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

test('events: create exige o perfil; update e delete continuam do dono', async () => {
  // sem perfil: negado
  await env.withSecurityRulesDisabled(async (ctx) => { await deleteDoc(doc(ctx.firestore(), 'users/alice')); });
  await assertFails(addDoc(collection(as('alice'), 'users/alice/events'), { title: 't' }));
  // com perfil: permitido
  await env.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), 'users/alice'), baseUser()); });
  await assertSucceeds(addDoc(collection(as('alice'), 'users/alice/events'), { title: 't' }));
  await assertSucceeds(setDoc(doc(as('alice'), 'users/alice/events/e1'), { title: 't' }));
  // update e delete sem perfil continuam permitidos ao dono (cascata da exclusao)
  await env.withSecurityRulesDisabled(async (ctx) => { await deleteDoc(doc(ctx.firestore(), 'users/alice')); });
  await assertSucceeds(updateDoc(doc(as('alice'), 'users/alice/events/e1'), { title: 't2' }));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'users/alice/events/e1')));
  // outro usuario continua negado
  await assertFails(setDoc(doc(as('bob'), 'users/alice/events/x'), { title: 'X' }));
});

test('users/{uid}/friends (modelo antigo) nao existe mais: create, leitura e delete negados ate ao dono', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), 'users/alice/friends/bob'), { name: 'B' }); });
  const a = as('alice');
  await assertFails(setDoc(doc(a, 'users/alice/friends/carol'), { name: 'C' }));
  await assertFails(getDoc(doc(a, 'users/alice/friends/bob')));
  await assertFails(getDocs(collection(a, 'users/alice/friends')));
  await assertFails(updateDoc(doc(a, 'users/alice/friends/bob'), { name: 'B2' }));
  await assertFails(deleteDoc(doc(a, 'users/alice/friends/bob')));
  await assertFails(setDoc(doc(as('bob'), 'users/alice/friends/x'), { name: 'X' }));
  // sem perfil tambem (cascata nao depende mais de friends)
  await env.withSecurityRulesDisabled(async (ctx) => { await deleteDoc(doc(ctx.firestore(), 'users/alice')); });
  await assertFails(deleteDoc(doc(a, 'users/alice/friends/bob')));
});

test('subcolecoes: so o dono', async () => {
  await assertSucceeds(addDoc(collection(as('alice'), 'users/alice/events'), { title: 't' }));
  await assertFails(addDoc(collection(as('bob'), 'users/alice/events'), { title: 't' }));
  await assertFails(getDocs(collection(as('bob'), 'users/alice/friends')));
  await assertFails(setDoc(doc(as('alice'), 'users/alice/outra/x'), { a: 1 }));
});

test('notificacao: amigo aceito + intencao fixa + nome real ok; forjar, texto livre e sem amizade negados; outro nao le', async () => {
  const n = (from, over = {}) => ({ type: 'intention', intentionId: 'luz', intentionLabel: 'Luz', fromName: 'A', fromUid: from, read: false, createdAt: serverTimestamp(), ...over });
  const col = (db) => collection(db, 'users/bob/notifications');
  // sem amizade: negado, mesmo com campos coerentes
  await assertFails(addDoc(col(as('alice')), n('alice')));
  await seedFs('alice', 'bob', { status: 'accepted', responderName: 'B', respondedAt: Timestamp.now() });
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

test('publicProfiles: logado le de outro; anonimo nao; consulta por emailHash ok', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'publicProfiles/bob'), pub({ name: 'B' }));
  });
  await assertSucceeds(getDoc(doc(as('alice'), 'publicProfiles/bob')));
  await assertSucceeds(getDocs(query(collection(as('alice'), 'publicProfiles'), where('emailHash', '==', HASH), limit(1))));
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
  await setDoc(doc(db, 'users/alice/notifications/n1'), { type: 'intention', fromUid: 'bob', read: false });
});

test('perfil ausente: dono ainda le e apaga conversas, mensagens, eventos e notificacoes', async () => {
  await seedAlice();
  const db = as('alice');
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
  await assertSucceeds(getDocs(collection(db, 'users/alice/conversations')));
  await assertSucceeds(getDocs(collection(db, 'users/alice/conversations/c1/messages')));
  await assertSucceeds(getDocs(collection(db, 'users/alice/events')));
  await assertSucceeds(getDocs(collection(db, 'users/alice/notifications')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/conversations/c1/messages/m0001')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/conversations/c1')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/events/e1')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/notifications/n1')));
  // apagar de novo (documento inexistente) e idempotente
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
});

test('perfil ausente: conversa nova (com e sem mensagem no batch) negada; com perfil ok', async () => {
  const db = as('alice');
  await assertSucceeds(setDoc(doc(db, 'users/alice/conversations/ok'), conv(0)));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
  // update e delete de conversa existente continuam do dono, sem perfil
  await assertSucceeds(updateDoc(doc(db, 'users/alice/conversations/ok'), { messageCount: 1, updatedAt: Timestamp.now() }));
  await assertFails(setDoc(doc(db, 'users/alice/conversations/n1'), conv(0)));
  const b = writeBatch(db);
  b.set(doc(db, 'users/alice/conversations/n2'), conv(1));
  b.set(doc(db, 'users/alice/conversations/n2/messages/m0001'), msg());
  await assertFails(b.commit());
  // outro usuario nunca cria na conversa alheia, com ou sem perfil
  await assertFails(setDoc(doc(as('bob'), 'users/alice/conversations/n3'), conv(0)));
  // recriado o perfil, o create volta a ser permitido
  await env.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), 'users/alice'), baseUser()); });
  await assertSucceeds(setDoc(doc(db, 'users/alice/conversations/n4'), conv(0)));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/conversations/n4')));
});

test('intencao: destino sem perfil (conta excluida) negada; com perfil ok', async () => {
  const n = { type: 'intention', intentionId: 'luz', intentionLabel: 'Luz', fromName: 'A', fromUid: 'alice', read: false, createdAt: serverTimestamp() };
  const acc = { status: 'accepted', responderName: 'X', respondedAt: Timestamp.now() };
  await seedFs('alice', 'bob', acc);
  await seedFs('alice', 'ghost', acc);
  await assertFails(addDoc(collection(as('alice'), 'users/ghost/notifications'), n));
  await assertSucceeds(addDoc(collection(as('alice'), 'users/bob/notifications'), n));
  await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'users/bob')));
  await assertFails(addDoc(collection(as('alice'), 'users/bob/notifications'), n));
});

test('intencao so entre amigos aceitos: sem relacao, pending, declined e apos remocao negadas; accepted nos dois sentidos ok', async () => {
  await seedFriendUsers();
  const n = (from, name) => ({ type: 'intention', intentionId: 'cura', intentionLabel: 'Cura', fromName: name, fromUid: from, read: false, createdAt: serverTimestamp() });
  const send = (from, to, name) => addDoc(collection(as(from), `users/${to}/notifications`), n(from, name));
  // sem relacao
  await assertFails(send('alice', 'bob', 'A'));
  // pendente (nos dois sentidos)
  await seedFs('alice', 'bob');
  await assertFails(send('alice', 'bob', 'A'));
  await assertFails(send('bob', 'alice', 'B'));
  // recusada
  await seedFs('alice', 'bob', { status: 'declined', declinedBy: 'bob', respondedAt: Timestamp.now() });
  await assertFails(send('alice', 'bob', 'A'));
  await assertFails(send('bob', 'alice', 'B'));
  // aceita: A->B e B->A
  await seedFs('alice', 'bob', { status: 'accepted', responderName: 'B', respondedAt: Timestamp.now() });
  await assertSucceeds(send('alice', 'bob', 'A'));
  await assertSucceeds(send('bob', 'alice', 'B'));
  // terceiro nao usa a amizade alheia
  await assertFails(send('carol', 'bob', 'C'));
  await assertFails(send('carol', 'alice', 'C'));
  // negacoes de sempre continuam: nome falso, rotulo trocado, destino excluido
  await assertFails(send('alice', 'bob', 'Outro'));
  await assertFails(addDoc(collection(as('alice'), 'users/bob/notifications'), { ...n('alice', 'A'), intentionLabel: 'Luz' }));
  // remover a amizade (alice) fecha o canal nos dois sentidos
  await assertSucceeds(updateDoc(fref(as('alice'), 'alice', 'bob'), { status: 'declined', declinedBy: 'alice', respondedAt: serverTimestamp() }));
  await assertFails(send('alice', 'bob', 'A'));
  await assertFails(send('bob', 'alice', 'B'));
  // destino excluido (sem users) nega mesmo com amizade aceita
  await seedFs('alice', 'bob', { status: 'accepted', responderName: 'B', respondedAt: Timestamp.now() });
  await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'users/bob')));
  await assertFails(send('alice', 'bob', 'A'));
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

test('economia: apos apagar e recriar o perfil, o teto e 575 (3 check-ins pela tolerancia de +-1 dia)', async () => {
  const db = as('alice');
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
  await assertSucceeds(setDoc(doc(db, 'users/alice'), baseUser()));
  const day = (off) => {
    const d = new Date(Date.now() + off * 86400000);
    return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
  };
  const ref = doc(db, 'users/alice');
  await assertSucceeds(updateDoc(ref, { dailyCheckIn: day(-1), 'wallet.stardust': 525 }));
  await assertSucceeds(updateDoc(ref, { dailyCheckIn: day(0), 'wallet.stardust': 550 }));
  await assertSucceeds(updateDoc(ref, { dailyCheckIn: day(1), 'wallet.stardust': 575 }));
  // a 4a data nao existe na janela; mesma data e saldo maior seguem negados
  await assertFails(updateDoc(ref, { dailyCheckIn: day(2), 'wallet.stardust': 600 }));
  await assertFails(updateDoc(ref, { dailyCheckIn: day(1), 'wallet.stardust': 600 }));
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

// ---- etapa 12: friendships (pedido, aceite, recusa, remocao)
test('friendships create: pedido valido de alice para bob ok e fica pending', async () => {
  await seedFriendUsers();
  await assertSucceeds(setDoc(fref(as('alice'), 'alice', 'bob'), reqDoc('alice', 'bob')));
  const d = await readFs('alice', 'bob');
  if (d.status !== 'pending' || d.requesterUid !== 'alice') throw new Error('pedido gravado errado');
  // o sentido inverso tambem cria (id e o mesmo, uids ordenados)
  await assertSucceeds(setDoc(fref(as('bob'), 'bob', 'carol'), reqDoc('bob', 'carol')));
});

test('friendships create: pedido a si mesmo, uids desordenados, id divergente e requesterUid alheio negados', async () => {
  await seedFriendUsers();
  const db = as('alice');
  await assertFails(setDoc(doc(db, 'friendships/alice_alice'), reqDoc('alice', 'alice')));
  await assertFails(setDoc(fref(db, 'alice', 'bob'), reqDoc('alice', 'bob', { uids: ['bob', 'alice'] })));
  await assertFails(setDoc(doc(db, 'friendships/alice_carol'), reqDoc('alice', 'bob')));
  await assertFails(setDoc(doc(db, 'friendships/bob_alice'), reqDoc('alice', 'bob')));
  await assertFails(setDoc(fref(db, 'alice', 'bob'), reqDoc('alice', 'bob', { requesterUid: 'bob' })));
  await assertFails(setDoc(fref(db, 'alice', 'bob'), reqDoc('alice', 'bob', { uids: ['alice', 'bob', 'carol'] })));
});

test('friendships create: status, nome, campo extra e createdAt invalidos negados', async () => {
  await seedFriendUsers();
  const db = as('alice');
  const ref = fref(db, 'alice', 'bob');
  await assertFails(setDoc(ref, reqDoc('alice', 'bob', { status: 'accepted' })));
  await assertFails(setDoc(ref, reqDoc('alice', 'bob', { status: 'declined' })));
  await assertFails(setDoc(ref, reqDoc('alice', 'bob', { requesterName: 'Outro Nome' })));
  await assertFails(setDoc(ref, reqDoc('alice', 'bob', { requesterName: '' })));
  await assertFails(setDoc(ref, reqDoc('alice', 'bob', { extra: 1 })));
  await assertFails(setDoc(ref, reqDoc('alice', 'bob', { responderName: 'B' })));
  await assertFails(setDoc(ref, reqDoc('alice', 'bob', { createdAt: Timestamp.fromMillis(1000) })));
  await assertFails(setDoc(ref, reqDoc('alice', 'bob', { createdAt: Timestamp.now() })));
  await assertSucceeds(setDoc(ref, reqDoc('alice', 'bob')));
});

test('friendships create: sem perfil do remetente, destino sem users, destino sem publicProfiles, anonimo e terceiro negados', async () => {
  await seedFriendUsers();
  // destino que desligou a busca (sem publicProfiles) nao recebe pedido
  await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'publicProfiles/bob')));
  await assertFails(setDoc(fref(as('alice'), 'alice', 'bob'), reqDoc('alice', 'bob')));
  // destino com publicProfiles mas sem users (conta excluida pela metade)
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'publicProfiles/ghost'), pub({ name: 'G' }));
  });
  await assertFails(setDoc(fref(as('alice'), 'alice', 'ghost'), reqDoc('alice', 'ghost')));
  // destino com users mas publicProfiles ausente: carol sem publicProfiles
  await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'publicProfiles/carol')));
  await assertFails(setDoc(fref(as('alice'), 'alice', 'carol'), reqDoc('alice', 'carol')));
  // anonimo
  await assertFails(setDoc(fref(env.unauthenticatedContext().firestore(), 'alice', 'bob'), reqDoc('alice', 'bob')));
  // terceiro (carol nao esta em uids) grava o par alice/bob
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'publicProfiles/carol'), pub({ name: 'C' })));
  await assertFails(setDoc(fref(as('carol'), 'alice', 'bob'), reqDoc('carol', 'bob', { uids: ['alice', 'bob'] })));
  await assertFails(setDoc(fref(as('carol'), 'alice', 'bob'), reqDoc('alice', 'bob')));
  // remetente sem perfil (exclusao em andamento)
  await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'users/alice')));
  await assertFails(setDoc(fref(as('alice'), 'alice', 'bob'), reqDoc('alice', 'bob')));
});

test('friendships duplicata e pedido cruzado: segundo create negado; o outro lado aceita', async () => {
  await seedFriendUsers();
  await assertSucceeds(setDoc(fref(as('alice'), 'alice', 'bob'), reqDoc('alice', 'bob')));
  // mesmo remetente de novo (vira update sem respondedAt): negado
  await assertFails(setDoc(fref(as('alice'), 'alice', 'bob'), reqDoc('alice', 'bob')));
  // pedido cruzado: bob tenta criar o par que alice ja criou
  await assertFails(setDoc(fref(as('bob'), 'alice', 'bob'), reqDoc('bob', 'alice')));
  const d = await readFs('alice', 'bob');
  if (d.requesterUid !== 'alice') throw new Error('o pedido original foi sobrescrito');
  // bob aceita o pedido de alice
  await assertSucceeds(updateDoc(fref(as('bob'), 'alice', 'bob'), { status: 'accepted', responderName: 'B', respondedAt: serverTimestamp() }));
});

test('friendships aceite: so o nao remetente; remetente, terceiro e anonimo negados', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob');
  const acc = { status: 'accepted', responderName: 'B', respondedAt: serverTimestamp() };
  await assertFails(updateDoc(fref(as('alice'), 'alice', 'bob'), { ...acc, responderName: 'A' }));
  await assertFails(updateDoc(fref(as('alice'), 'alice', 'bob'), acc));
  await assertFails(updateDoc(fref(as('carol'), 'alice', 'bob'), { ...acc, responderName: 'C' }));
  await assertFails(updateDoc(fref(env.unauthenticatedContext().firestore(), 'alice', 'bob'), acc));
  await assertFails(updateDoc(fref(as('root'), 'alice', 'bob'), acc));
  await assertSucceeds(updateDoc(fref(as('bob'), 'alice', 'bob'), acc));
  const d = await readFs('alice', 'bob');
  if (d.status !== 'accepted' || d.responderName !== 'B') throw new Error('aceite nao gravado');
});

test('friendships aceite: campos que o destinatario nao pode alterar e valores invalidos negados', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob');
  const ref = fref(as('bob'), 'alice', 'bob');
  const acc = { status: 'accepted', responderName: 'B', respondedAt: serverTimestamp() };
  await assertFails(updateDoc(ref, { ...acc, uids: ['bob', 'carol'] }));
  await assertFails(updateDoc(ref, { ...acc, requesterUid: 'bob' }));
  await assertFails(updateDoc(ref, { ...acc, requesterName: 'Falso' }));
  await assertFails(updateDoc(ref, { ...acc, createdAt: Timestamp.fromMillis(5) }));
  await assertFails(updateDoc(ref, { ...acc, declinedBy: 'bob' }));
  await assertFails(updateDoc(ref, { ...acc, extra: 1 }));
  await assertFails(updateDoc(ref, { ...acc, responderName: 'Nome Falso' }));
  await assertFails(updateDoc(ref, { ...acc, respondedAt: Timestamp.fromMillis(5) }));
  await assertFails(updateDoc(ref, { status: 'accepted', responderName: 'B' })); // sem respondedAt
  await assertFails(updateDoc(ref, { status: 'pending', respondedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, acc));
});

test('friendships aceite duplo e transicoes invalidas: accepted->accepted, declined->accepted negados', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob');
  const acc = { status: 'accepted', responderName: 'B', respondedAt: serverTimestamp() };
  await assertSucceeds(updateDoc(fref(as('bob'), 'alice', 'bob'), acc));
  await assertFails(updateDoc(fref(as('bob'), 'alice', 'bob'), { ...acc, respondedAt: serverTimestamp() }));
  // lapide nao volta a aceita
  await seedFs('alice', 'carol', { status: 'declined', declinedBy: 'carol', respondedAt: Timestamp.now() });
  await assertFails(updateDoc(fref(as('carol'), 'alice', 'carol'), { ...acc, responderName: 'C' }));
  await assertFails(updateDoc(fref(as('alice'), 'alice', 'carol'), { status: 'accepted', respondedAt: serverTimestamp() }));
});

test('friendships aceite: remetente com a conta excluida (sem users) negado', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob');
  await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'users/alice')));
  await assertFails(updateDoc(fref(as('bob'), 'alice', 'bob'), { status: 'accepted', responderName: 'B', respondedAt: serverTimestamp() }));
  // recusar continua possivel (nao depende do remetente)
  await assertSucceeds(updateDoc(fref(as('bob'), 'alice', 'bob'), { status: 'declined', declinedBy: 'bob', respondedAt: serverTimestamp() }));
});

test('friendships recusa e lapide: recusa so por quem nao pediu; lapide nao e recriada, alterada nem apagada pelo recusado', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob');
  const dec = (by) => ({ status: 'declined', declinedBy: by, respondedAt: serverTimestamp() });
  // o remetente nao recusa o proprio pedido; terceiro e anonimo negados
  await assertFails(updateDoc(fref(as('alice'), 'alice', 'bob'), dec('alice')));
  await assertFails(updateDoc(fref(as('carol'), 'alice', 'bob'), dec('carol')));
  await assertFails(updateDoc(fref(env.unauthenticatedContext().firestore(), 'alice', 'bob'), dec('bob')));
  // declinedBy de outro negado
  await assertFails(updateDoc(fref(as('bob'), 'alice', 'bob'), dec('alice')));
  // responderName junto da recusa negado
  await assertFails(updateDoc(fref(as('bob'), 'alice', 'bob'), { ...dec('bob'), responderName: 'B' }));
  await assertSucceeds(updateDoc(fref(as('bob'), 'alice', 'bob'), dec('bob')));
  // lapide: alice nao recria, nao altera, nao apaga
  const a = as('alice');
  await assertFails(setDoc(fref(a, 'alice', 'bob'), reqDoc('alice', 'bob')));
  await assertFails(updateDoc(fref(a, 'alice', 'bob'), { status: 'pending', respondedAt: serverTimestamp() }));
  await assertFails(updateDoc(fref(a, 'alice', 'bob'), { status: 'accepted', responderName: 'A', respondedAt: serverTimestamp() }));
  await assertFails(updateDoc(fref(a, 'alice', 'bob'), { declinedBy: 'alice', respondedAt: serverTimestamp() }));
  await assertFails(deleteDoc(fref(a, 'alice', 'bob')));
  const d = await readFs('alice', 'bob');
  if (d.status !== 'declined' || d.declinedBy !== 'bob') throw new Error('lapide foi alterada');
});

test('friendships desbloqueio: quem recusou apaga a lapide e o par pode ser criado de novo', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob', { status: 'declined', declinedBy: 'bob', respondedAt: Timestamp.now() });
  await assertFails(deleteDoc(fref(as('carol'), 'alice', 'bob')));
  await assertFails(deleteDoc(fref(as('alice'), 'alice', 'bob')));
  await assertSucceeds(deleteDoc(fref(as('bob'), 'alice', 'bob')));
  if ((await readFs('alice', 'bob')) !== null) throw new Error('lapide nao foi apagada');
  await assertSucceeds(setDoc(fref(as('alice'), 'alice', 'bob'), reqDoc('alice', 'bob')));
});

test('friendships remocao: qualquer um dos dois remove uma amizade aceita; terceiro negado; remover vira lapide de quem removeu', async () => {
  await seedFriendUsers();
  const acc = { status: 'accepted', responderName: 'B', respondedAt: Timestamp.now() };
  await seedFs('alice', 'bob', acc);
  const dec = (by) => ({ status: 'declined', declinedBy: by, respondedAt: serverTimestamp() });
  await assertFails(updateDoc(fref(as('carol'), 'alice', 'bob'), dec('carol')));
  await assertFails(updateDoc(fref(as('alice'), 'alice', 'bob'), dec('bob')));
  await assertSucceeds(updateDoc(fref(as('alice'), 'alice', 'bob'), dec('alice')));
  // bob (recusado) nao recria nem apaga a lapide de alice
  await assertFails(setDoc(fref(as('bob'), 'alice', 'bob'), reqDoc('bob', 'alice')));
  await assertFails(deleteDoc(fref(as('bob'), 'alice', 'bob')));
  // o outro sentido: bob remove
  await seedFs('alice', 'bob', acc);
  await assertSucceeds(updateDoc(fref(as('bob'), 'alice', 'bob'), dec('bob')));
});

test('friendships cancelar: remetente apaga pending; destinatario nao; ninguem apaga accepted com perfil', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob');
  await assertFails(deleteDoc(fref(as('bob'), 'alice', 'bob')));
  await assertFails(deleteDoc(fref(as('carol'), 'alice', 'bob')));
  await assertFails(deleteDoc(fref(as('root'), 'alice', 'bob')));
  await assertFails(deleteDoc(fref(env.unauthenticatedContext().firestore(), 'alice', 'bob')));
  await assertSucceeds(deleteDoc(fref(as('alice'), 'alice', 'bob')));
  await seedFs('alice', 'bob', { status: 'accepted', responderName: 'B', respondedAt: Timestamp.now() });
  await assertFails(deleteDoc(fref(as('alice'), 'alice', 'bob')));
  await assertFails(deleteDoc(fref(as('bob'), 'alice', 'bob')));
});

test('friendships exclusao de conta: sem users/{eu} o membro apaga qualquer relacao sua (inclusive lapide em que foi recusado); terceiros nao', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob', { status: 'accepted', responderName: 'B', respondedAt: Timestamp.now() });
  await seedFs('alice', 'carol', { status: 'declined', declinedBy: 'carol', respondedAt: Timestamp.now() });
  await seedFs('bob', 'carol');
  await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'users/alice')));
  const a = as('alice');
  await assertSucceeds(deleteDoc(fref(a, 'alice', 'bob')));
  await assertSucceeds(deleteDoc(fref(a, 'alice', 'carol')));
  // relacao de que alice nao faz parte: negado mesmo sem perfil
  await assertFails(deleteDoc(fref(a, 'bob', 'carol')));
  // a consulta da cascata funciona sem perfil
  await assertSucceeds(getDocs(query(collection(a, 'friendships'), where('uids', 'array-contains', 'alice'))));
  // bob (com perfil) nao apaga a relacao accepted de outra forma
  await seedFs('alice', 'bob', { status: 'accepted', responderName: 'B', respondedAt: Timestamp.now() });
  await assertFails(deleteDoc(fref(as('bob'), 'alice', 'bob')));
});

test('friendships leitura: get do par proprio (inclusive inexistente) ok; par alheio, anonimo e admin negados', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob');
  await assertSucceeds(getDoc(fref(as('alice'), 'alice', 'bob')));
  await assertSucceeds(getDoc(fref(as('bob'), 'alice', 'bob')));
  await assertSucceeds(getDoc(fref(as('alice'), 'alice', 'carol'))); // inexistente, mas meu par
  await assertFails(getDoc(fref(as('carol'), 'alice', 'bob')));
  await assertFails(getDoc(fref(as('bob'), 'alice', 'carol')));
  await assertFails(getDoc(fref(as('root'), 'alice', 'bob')));
  await assertFails(getDoc(fref(env.unauthenticatedContext().firestore(), 'alice', 'bob')));
});

test('friendships leitura: query array-contains com o proprio uid ok; uid alheio, sem filtro, collection group e anonimo negados', async () => {
  await seedFriendUsers();
  await seedFs('alice', 'bob');
  await seedFs('bob', 'carol');
  const q = (db, uid) => query(collection(db, 'friendships'), where('uids', 'array-contains', uid));
  const mine = await assertSucceeds(getDocs(q(as('alice'), 'alice')));
  if (mine.size !== 1) throw new Error(`esperava 1 relacao, veio ${mine.size}`);
  const bobs = await assertSucceeds(getDocs(q(as('bob'), 'bob')));
  if (bobs.size !== 2) throw new Error(`esperava 2 relacoes, veio ${bobs.size}`);
  await assertFails(getDocs(q(as('alice'), 'bob')));
  await assertFails(getDocs(collection(as('alice'), 'friendships')));
  await assertFails(getDocs(query(collectionGroup(as('alice'), 'friendships'), where('uids', 'array-contains', 'alice'))));
  await assertFails(getDocs(q(env.unauthenticatedContext().firestore(), 'alice')));
  await assertFails(getDocs(q(as('root'), 'alice')));
});

test('friendships: uids reais de 28 caracteres funcionam (pedido, aceite, leitura)', async () => {
  const u1 = 'aB3dE5gH7jK9mN1pQ3sT5vW7yZ01';
  const u2 = 'zY9xW7vU5tS3rQ1pO9nM7lK5jI3h';
  if (u1.length !== 28 || u2.length !== 28) throw new Error('uids de teste invalidos');
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${u1}`), baseUser({ name: 'U1' }));
    await setDoc(doc(db, `users/${u2}`), baseUser({ name: 'U2' }));
    await setDoc(doc(db, `publicProfiles/${u2}`), pub({ name: 'U2' }));
  });
  const [lo, hi] = [u1, u2].sort();
  const ref = (db) => doc(db, `friendships/${lo}_${hi}`);
  await assertSucceeds(setDoc(ref(as(u1)), {
    uids: [lo, hi], requesterUid: u1, requesterName: 'U1', status: 'pending', createdAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(ref(as(u2))));
  await assertSucceeds(updateDoc(ref(as(u2)), { status: 'accepted', responderName: 'U2', respondedAt: serverTimestamp() }));
});

test('friendships exclusao de conta: batch de 400 deletes (pagina da cascata) sem perfil passa nos limites de exists()', async () => {
  await seedFriendUsers();
  const ids = [];
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (let i = 0; i < 400; i++) {
      const other = `u${String(i).padStart(4, '0')}`;
      const [lo, hi] = ['alice', other].sort();
      ids.push(`${lo}_${hi}`);
      await setDoc(doc(db, `friendships/${lo}_${hi}`), {
        uids: [lo, hi], requesterUid: i % 2 ? 'alice' : other, requesterName: 'X',
        status: ['pending', 'accepted', 'declined'][i % 3], createdAt: Timestamp.now(),
        ...(i % 3 === 2 ? { declinedBy: other } : {}),
      });
    }
    await deleteDoc(doc(db, 'users/alice'));
  });
  const db = as('alice');
  const b = writeBatch(db);
  for (const id of ids) b.delete(doc(db, `friendships/${id}`));
  await assertSucceeds(b.commit());
  const left = await getDocs(query(collection(as('alice'), 'friendships'), where('uids', 'array-contains', 'alice')));
  if (left.size !== 0) throw new Error(`sobraram ${left.size} relacoes`);
});

// ---- etapa 12, passo 7: publicProfiles com list limitado (busca por hash = limit(1))
test('publicProfiles list: busca por hash com limit(1) ok; sem limit, limit > 1, sem filtro e anonimo negados', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'publicProfiles/bob'), pub({ name: 'B' }));
    await setDoc(doc(db, 'publicProfiles/carol'), pub({ name: 'C', emailHash: 'b'.repeat(64) }));
  });
  const col = (db) => collection(db, 'publicProfiles');
  const found = await assertSucceeds(getDocs(query(col(as('alice')), where('emailHash', '==', HASH), limit(1))));
  if (found.size !== 1) throw new Error(`esperava 1 perfil, veio ${found.size}`);
  await assertSucceeds(getDocs(query(col(as('alice')), limit(1))));
  await assertFails(getDocs(query(col(as('alice')), where('emailHash', '==', HASH))));
  await assertFails(getDocs(query(col(as('alice')), where('emailHash', '==', HASH), limit(2))));
  await assertFails(getDocs(col(as('alice'))));
  await assertFails(getDocs(query(col(as('alice')), limit(500))));
  await assertFails(getDocs(query(col(env.unauthenticatedContext().firestore()), where('emailHash', '==', HASH), limit(1))));
  // get por uid continua livre para logados
  await assertSucceeds(getDoc(doc(as('alice'), 'publicProfiles/carol')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'publicProfiles/carol')));
});
