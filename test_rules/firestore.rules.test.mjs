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

test('notificacao: enviar a outro com fromUid proprio ok; forjar negado; outro nao le', async () => {
  const n = (from) => ({ type: 'intention', intentionId: 'i', intentionLabel: 'l', fromName: 'A', fromUid: from, read: false, createdAt: serverTimestamp() });
  await assertSucceeds(addDoc(collection(as('alice'), 'users/bob/notifications'), n('alice')));
  await assertFails(addDoc(collection(as('alice'), 'users/bob/notifications'), n('carol')));
  await assertFails(getDocs(collection(as('alice'), 'users/bob/notifications')));
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
