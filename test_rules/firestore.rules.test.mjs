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
    firestore: { rules: fs.readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
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
    for (const id of ['a', 'b', 'skin_x', 'bg_y']) {
      await setDoc(doc(db, `shop_items/${id}`), item(100));
    }
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

test('delete do perfil negado', async () => {
  await assertFails(deleteDoc(doc(as('alice'), 'users/alice')));
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
