import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LIENS, messageFcm, SITE, type EnvoiPush } from '../src/notifications';

const push: EnvoiPush = {
  titre: 'Moussa Diop',
  corps: 'Je suis devant la pharmacie',
  canal: 'messages',
  lien: LIENS.messagesClient,
  donnees: { type: 'message', courseId: 'c1' },
  dureeVieSecondes: 3600,
};

test('message FCM : le texte de la notification est celui du message, pour Android comme pour le site', () => {
  const m = messageFcm(['a', 'b'], push);
  assert.deepEqual(m.tokens, ['a', 'b']);
  assert.deepEqual(m.notification, { title: 'Moussa Diop', body: 'Je suis devant la pharmacie' });
  assert.deepEqual(m.data, { type: 'message', courseId: 'c1' });
});

test('partie Android : priorité haute, canal choisi, durée de vie', () => {
  const { android } = messageFcm(['a'], push);
  assert.equal(android?.priority, 'high');
  assert.equal(android?.ttl, 3600 * 1000);
  assert.equal(android?.notification?.channelId, 'messages');
});

test('partie site (navigateur, iPhone) : lien absolu en https, icône, priorité haute, durée de vie', () => {
  const { webpush } = messageFcm(['a'], push);
  assert.equal(webpush?.fcmOptions?.link, `${SITE}/#/accueil/messages`);
  assert.ok(webpush?.fcmOptions?.link?.startsWith('https://'));
  assert.equal(webpush?.notification?.['icon'], `${SITE}/icons/Icon-192.png`);
  assert.equal(webpush?.headers?.Urgency, 'high');
  assert.equal(webpush?.headers?.TTL, '3600');
});

test('course : durée de vie courte pour la partie site aussi', () => {
  const m = messageFcm(['a'], { ...push, canal: 'courses', lien: LIENS.chauffeur, dureeVieSecondes: 120 });
  assert.equal(m.webpush?.headers?.TTL, '120');
  assert.equal(m.android?.notification?.channelId, 'courses');
  assert.equal(m.webpush?.fcmOptions?.link, `${SITE}/#/conducteur`);
});
