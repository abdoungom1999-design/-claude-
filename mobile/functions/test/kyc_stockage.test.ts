import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cheminDocument, decoderDataUri, documentsBase64 } from '../src/kyc_stockage';

const PIXEL = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/';

test('decoderDataUri : image Base64 décodée avec son type', () => {
  const d = decoderDataUri(`data:image/jpeg;base64,${PIXEL}`);
  assert.ok(d);
  assert.equal(d.typeMime, 'image/jpeg');
  assert.equal(d.octets.toString('base64'), PIXEL);
});

test('decoderDataUri : URL Storage, autre type, base64 vide ou valeur absente → null', () => {
  assert.equal(decoderDataUri('https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media&token=t'), null);
  assert.equal(decoderDataUri('data:text/html;base64,PGgxPg=='), null);
  assert.equal(decoderDataUri('data:image/jpeg;base64,'), null);
  assert.equal(decoderDataUri(undefined), null);
  assert.equal(decoderDataUri(42), null);
});

test('cheminDocument : même emplacement que l\'app et les règles Storage', () => {
  assert.equal(cheminDocument('uid1', 'permis'), 'kyc_documents/uid1/permis.jpg');
});

test('documentsBase64 : seuls les documents encore encodés, parmi les clés connues', () => {
  const trouves = documentsBase64({
    documents: {
      permis: 'data:image/jpeg;base64,AAAA',
      carteGrise: 'https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media&token=t',
      attestationVtc: 'data:image/jpeg;base64,BBBB',
      inconnu: 'data:image/jpeg;base64,CCCC',
    },
  });
  assert.deepEqual(trouves, { permis: 'data:image/jpeg;base64,AAAA', attestationVtc: 'data:image/jpeg;base64,BBBB' });
  assert.deepEqual(documentsBase64({}), {});
  assert.deepEqual(documentsBase64({ documents: 'x' }), {});
});
