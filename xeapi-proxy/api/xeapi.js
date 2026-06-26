// Classicism — XEAPI Cloud Function Proxy (Cloudflare Workers)
// Self-contained: uses Node.js built-in crypto/zlib via nodejs_compat.
// Deploy with: wrangler deploy

import crypto from 'node:crypto';
import zlib from 'node:zlib';

// ============================================================
// Constants
// ============================================================

const eapiKey = 'e82ckenh8dichen8';
const xeapiStaticKey = Buffer.from(
  'ab1d5a430f6bb04a3f01e81ddd72bd916d5ce591248ac128714806d7f8fb1b84',
  'hex',
);
const xeapiSignKey =
  'mUHCwVNWJbunMqAHf5MImuirT6plvs6VSFW62MGHstFQxhBGdEoIhLItH3djc4+FB/OKty3+lL2rGeoFBpVe5g==';
const x25519SpkiPrefix = Buffer.from('302a300506032b656e032100', 'hex');

const XEAPI_DOMAIN = 'interface3.music.163.com';
const API_DOMAIN = 'interface.music.163.com';

// ============================================================
// In-memory state
// ============================================================

let publicKeyState = null;
let sessionId = '';
let sessionKey = null;

// ============================================================
// Crypto helpers
// ============================================================

function aesEcbEncrypt(key, plaintext) {
  const cipher = crypto.createCipheriv(`aes-${key.length * 8}-ecb`, key, null);
  return Buffer.concat([cipher.update(Buffer.from(plaintext)), cipher.final()]);
}

function aesEcbDecrypt(key, ciphertext) {
  const decipher = crypto.createDecipheriv(`aes-${key.length * 8}-ecb`, key, null);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

function createX25519PublicKey(raw) {
  return crypto.createPublicKey({
    key: Buffer.concat([x25519SpkiPrefix, raw]),
    format: 'der',
    type: 'spki',
  });
}

function deriveX25519AesKey(sharedSecret, ephemeralPublicKey) {
  const prk = crypto
    .createHmac('sha256', Buffer.alloc(32))
    .update(sharedSecret.length ? sharedSecret : Buffer.alloc(32))
    .digest();
  return crypto
    .createHmac('sha256', prk)
    .update(Buffer.concat([ephemeralPublicKey, Buffer.from([1])]))
    .digest()
    .subarray(0, 16);
}

function xeapiSign(timestamp, nonce) {
  return crypto
    .createHmac('sha256', xeapiSignKey)
    .update(String(timestamp) + nonce)
    .digest('base64');
}

function xeapiDecryptPublicKey(encryptedData) {
  return JSON.parse(
    aesEcbDecrypt(xeapiStaticKey, Buffer.from(encryptedData, 'base64')).toString(),
  );
}

function xeapiMidTransform(ciphertext) {
  const random = crypto.randomBytes(16);
  const xored = Buffer.alloc(ciphertext.length);
  for (let i = 0; i < ciphertext.length; i++) {
    xored[i] = ciphertext[i] ^ random[i & 0x0f];
  }
  const b64 = Buffer.from(xored.toString('base64'));
  const rot = b64.length ? (random[0] & 0x0f) % b64.length : 0;
  return Buffer.concat([random, b64.subarray(rot), b64.subarray(0, rot)]);
}

function xeapiEncryptS(dynamicKey, pkState, os) {
  const peerRaw = Buffer.from(pkState.publicKey, 'base64');
  const peerKey = createX25519PublicKey(peerRaw);
  const { publicKey, privateKey } = crypto.generateKeyPairSync('x25519');
  const ephemeralRaw = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
  const sharedSecret = crypto.diffieHellman({ privateKey, publicKey: peerKey });
  const aesKey = deriveX25519AesKey(sharedSecret, ephemeralRaw);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-128-gcm', aesKey, iv);
  const plaintext = Buffer.from(`${dynamicKey.toString('base64')}|${os}|${pkState.sk || ''}`);
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([ephemeralRaw, iv, encrypted, cipher.getAuthTag()]);
}

function buildXeapiPlaintext(uri, data) {
  const fields = {};
  const url = new URL(uri, `https://${API_DOMAIN}`);
  if (url.search) fields.queryString = url.search.slice(1);
  if (data && Object.keys(data).length > 0) {
    fields.body = Buffer.from(new URLSearchParams(data).toString()).toString('base64');
  }
  fields.queryString = fields.queryString ? fields.queryString + '&e_r=true' : 'e_r=true';
  return JSON.stringify(fields);
}

function xeapi(uri, data) {
  if (!publicKeyState) throw new Error('xeapi publicKeyState not available');
  const os = 'android';
  const dynamicKey = sessionKey || crypto.randomBytes(16);
  const plaintext = Buffer.from(buildXeapiPlaintext(uri, data));
  const b = aesEcbEncrypt(dynamicKey, xeapiMidTransform(aesEcbEncrypt(xeapiStaticKey, plaintext)));
  const s = xeapiEncryptS(dynamicKey, publicKeyState, os);
  const r = aesEcbEncrypt(xeapiStaticKey, Buffer.from(`${publicKeyState.version}|${sessionKey ? sessionId : ''}`));
  return { B: b.toString('base64'), S: s.toString('base64'), R: r.toString('base64') };
}

function xeapiResDecrypt(body) {
  const decrypted = aesEcbDecrypt(Buffer.from(eapiKey), body);
  const plaintext = decrypted[0] === 0x1f && decrypted[1] === 0x8b ? zlib.gunzipSync(decrypted) : decrypted;
  return JSON.parse(plaintext.toString());
}

// ============================================================
// X25519 Key Registration
// ============================================================

function generateNonce() {
  return Array.from({ length: 16 }, () => Math.floor(Math.random() * 10)).join('');
}

async function registerXeapiKey(deviceId) {
  const nonce = generateNonce();
  const timestamp = String(Date.now());
  const body = new URLSearchParams({
    appVersion: '9.1.65',
    currentKeyVersion: publicKeyState?.version || '',
    deviceId: deviceId || '',
    nonce,
    os: 'android',
    requestType: 'active',
    signature: xeapiSign(timestamp, nonce),
    t1: '', t2: '', timestamp, uid: '',
  }).toString();

  const res = await fetch(`https://${API_DOMAIN}/api/gorilla/anti/crawler/security/key/get`, {
    method: 'POST',
    headers: {
      'User-Agent': 'NeteaseMusic/9.1.65.240927161425(9001065);Dalvik/2.1.0 (Linux; U; Android 14; 23013RK75C Build/UKQ1.230804.001)',
      'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
      Cookie: deviceId ? `deviceId=${encodeURIComponent(deviceId)}` : '',
    },
    body,
  });

  const json = await res.json();
  if (!json?.data?.encryptedData) throw new Error('xeapi public key request failed');

  const serverSig = json.data.signature;
  const serverTs = json.data.timestamp;
  if (!serverSig || xeapiSign(serverTs, nonce) !== serverSig) {
    throw new Error('xeapi public key response signature mismatch');
  }

  const keyData = xeapiDecryptPublicKey(json.data.encryptedData);
  if (!keyData.sk) throw new Error('xeapi response missing sk');

  publicKeyState = {
    publicKey: keyData.publicKey,
    version: keyData.version || keyData.expireTime || 0,
    sk: keyData.sk,
    expireTime: keyData.expireTime || 0,
  };
  return publicKeyState;
}

// ============================================================
// Main Worker
// ============================================================

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    if (request.method !== 'POST') {
      return Response.json({ error: 'Method not allowed' }, { status: 405 });
    }

    try {
      const { endpoint, data, cookie, deviceId } = await request.json();
      if (!endpoint) {
        return Response.json({ error: 'endpoint is required' }, { status: 400 });
      }

      // Ensure public key
      const now = Date.now();
      if (!publicKeyState || (publicKeyState.expireTime && publicKeyState.expireTime * 1000 < now)) {
        await registerXeapiKey(deviceId);
      }

      // Encrypt request
      const encrypted = xeapi(endpoint, data || {});

      // Forward to Netease
      const res = await fetch(`https://${XEAPI_DOMAIN}/xeapi${endpoint}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
          'User-Agent': 'NeteaseMusic/9.1.65.240927161425(9001065);Dalvik/2.1.0 (Linux; U; Android 14; 23013RK75C Build/UKQ1.230804.001)',
          'X-Client-Enc-State': 'ENCRYPTED',
          'x-aeapi': 'true',
          Cookie: cookie || '',
        },
        body: new URLSearchParams(encrypted).toString(),
      });

      // Handle session keys
      const encrSsid = res.headers.get('x-encr-ssid');
      const encrSskey = res.headers.get('x-encr-sskey');
      if (encrSsid && encrSskey) {
        sessionId = encrSsid;
        sessionKey = Buffer.from(encrSskey, 'base64');
      }

      // Extract cookies
      const cookies = (res.headers.getSetCookie?.() || []).map(
        (x) => x.replace(/\s*Domain=[^(;|$)]+;*/, ''),
      );

      // Decrypt response
      const raw = Buffer.from(await res.arrayBuffer());
      const body = xeapiResDecrypt(raw);

      return Response.json(
        { body, cookie: cookies },
        {
          headers: {
            'Access-Control-Allow-Origin': '*',
          },
        },
      );
    } catch (e) {
      console.error('xeapi proxy error:', e);
      return Response.json(
        { error: e.message || 'Internal error' },
        { status: 502, headers: { 'Access-Control-Allow-Origin': '*' } },
      );
    }
  },
};
