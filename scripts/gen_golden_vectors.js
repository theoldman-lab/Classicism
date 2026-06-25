/**
 * Phase 1 Golden Vector Generator
 *
 * Generates deterministic test vectors from util/crypto.js for verifying
 * the Dart implementation byte-for-byte.
 *
 * Usage: node scripts/gen_golden_vectors.js
 * Output: test/golden_vectors.json (or stdout)
 */
const path = require('path')
const fs = require('fs')

// ---- Load crypto module ----
const crypto = require('../util/crypto')
const CryptoJS = require('crypto-js')

// ---- Deterministic PRNG for mocking Math.random ----
let _seed = 12345
function mockRandom() {
  _seed = (_seed * 16807 + 0) % 2147483647
  return (_seed - 1) / 2147483646
}

// ---- Constants from crypto.js (not exported, read from source) ----
const BASE62 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
const EAPI_KEY = 'e82ckenh8dichen8'
const RSA_PEM = `-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB
-----END PUBLIC KEY-----`

// ---- Monkey-patch Math.random for deterministic weapi output ----
const originalRandom = Math.random
function withMockedRandom(fn) {
  Math.random = mockRandom
  _seed = 12345 // reset seed before each call
  try {
    return fn()
  } finally {
    Math.random = originalRandom
  }
}

// ---- Helpers ----
function hexToBytes(hex) {
  const bytes = []
  for (let i = 0; i < hex.length; i += 2) {
    bytes.push(parseInt(hex.substring(i, i + 2), 16))
  }
  return bytes
}

// ---- Test payloads ----
const golden = {
  meta: {
    description: 'Golden test vectors for Phase 1 crypto port',
    generatedAt: new Date().toISOString(),
    source: 'util/crypto.js',
  },
  md5: {},
  eapi: {},
  weapi: {},
  aes: {},
  rsa: {},
}

// ============================================================
// 0. MD5 vectors (independent verification)
// ============================================================

const md5Tests = [
  { name: 'empty', input: '' },
  { name: 'hello', input: 'hello' },
  {
    name: 'eapi_digest_search',
    input: 'nobody/api/search/getuse{"s":"test","type":"1","limit":"30"}md5forencrypt',
  },
  {
    name: 'eapi_digest_chinese',
    input: 'nobody/api/search/getuse{"s":"周杰伦","type":"1","limit":"30"}md5forencrypt',
  },
]

for (const t of md5Tests) {
  golden.md5[t.name] = {
    input: t.input,
    digest: CryptoJS.MD5(t.input).toString(),
    digestLength: 32,
  }
}

// ============================================================
// 1. EAPI vectors (no randomness → fully deterministic)
// ============================================================

const eapiTests = [
  {
    name: 'search_simple',
    url: '/api/search/get',
    data: { s: 'test', type: '1', limit: '30' },
  },
  {
    name: 'search_chinese',
    url: '/api/search/get',
    data: { s: '周杰伦', type: '1', limit: '30' },
  },
  {
    name: 'login_qr_key',
    url: '/api/login/qrcode/unikey',
    data: { type: '3' },
  },
  {
    name: 'login_qr_check',
    url: '/api/login/qrcode/client/login',
    data: { key: 'test-unikey-123', type: '3' },
  },
  {
    name: 'song_detail',
    url: '/api/v3/song/detail',
    data: { c: '[{"id":186016}]' },
  },
  {
    name: 'playlist_detail',
    url: '/api/v6/playlist/detail',
    data: { id: '3778678', n: '10', s: '0' },
  },
  {
    name: 'lyric',
    url: '/api/song/lyric',
    data: { id: '186016' },
  },
  {
    name: 'empty_object',
    url: '/api/test',
    data: {},
  },
]

for (const test of eapiTests) {
  const result = crypto.eapi(test.url, test.data)

  // Verify round-trip: decrypt the encrypted hex back to structured data
  const rawDecrypted = crypto.aesDecrypt(result.params, EAPI_KEY, '', 'hex')
  const decryptedUtf8 = rawDecrypted.toString(require('crypto-js').enc.Utf8)

  golden.eapi[test.name] = {
    url: test.url,
    data: test.data,
    params: result.params,
    paramsLength: result.params.length,
    // Store decrypted structure for verifying the cipher logic independently
    decryptedStructure: decryptedUtf8,
  }
}

// ============================================================
// 2. AES low-level verify (ECB encrypt/decrypt, CBC encrypt)
// ============================================================

// AES-ECB encrypt with known key + plaintext
const aesEcbInputs = [
  { name: 'ecb_hello', key: 'e82ckenh8dichen8', plaintext: 'hello world' },
  { name: 'ecb_json', key: 'e82ckenh8dichen8', plaintext: '{"a":1}' },
  {
    name: 'ecb_16bytes',
    key: 'e82ckenh8dichen8',
    plaintext: '0123456789ABCDEF',
  },
  {
    name: 'ecb_eapi_data',
    key: 'e82ckenh8dichen8',
    plaintext: '/api/search/get-36cd479b6b5-{"s":"test","type":"1","limit":"30"}-36cd479b6b5-047446cca5a7313b1653933a331667a4',
  },
]

for (const t of aesEcbInputs) {
  const cipher = CryptoJS.AES.encrypt(
    CryptoJS.enc.Utf8.parse(t.plaintext),
    CryptoJS.enc.Utf8.parse(t.key),
    { mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.Pkcs7 },
  )
  const hex = cipher.ciphertext.toString().toUpperCase()
  const decrypted = CryptoJS.AES.decrypt(cipher, CryptoJS.enc.Utf8.parse(t.key), {
    mode: CryptoJS.mode.ECB,
    padding: CryptoJS.pad.Pkcs7,
  })
  const decryptedStr = decrypted.toString(CryptoJS.enc.Utf8)

  // Also test hex-input decryption (as used in eapiResDecrypt)
  const hexDecrypted = CryptoJS.AES.decrypt(
    { ciphertext: CryptoJS.enc.Hex.parse(hex) },
    CryptoJS.enc.Utf8.parse(t.key),
    { mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.Pkcs7 },
  )
  const hexDecryptedStr = hexDecrypted.toString(CryptoJS.enc.Utf8)

  golden.aes[t.name] = {
    mode: 'ECB',
    key: t.key,
    plaintext: t.plaintext,
    ciphertextHex: hex,
    ciphertextLength: hex.length,
    decrypted: decryptedStr,
    roundtripOk: decryptedStr === t.plaintext,
    hexDecryptOk: hexDecryptedStr === t.plaintext,
  }
}

// AES-CBC encrypt
const aesCbcInputs = [
  { name: 'cbc_hello', key: '0CoJUm6Qyw8W8jud', iv: '0102030405060708', plaintext: 'hello world' },
  { name: 'cbc_json', key: '0CoJUm6Qyw8W8jud', iv: '0102030405060708', plaintext: '{"phone":"13800138000","password":"abc123"}' },
  {
    name: 'cbc_double', key: '0CoJUm6Qyw8W8jud', iv: '0102030405060708',
    plaintext: '{"phone":"13800138000","password":"abc123","rememberLogin":"true"}',
  },
]

for (const t of aesCbcInputs) {
  const cipher = CryptoJS.AES.encrypt(
    CryptoJS.enc.Utf8.parse(t.plaintext),
    CryptoJS.enc.Utf8.parse(t.key),
    { iv: CryptoJS.enc.Utf8.parse(t.iv), mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7 },
  )
  const base64 = cipher.toString()
  const base64FromCiphertext = cipher.ciphertext.toString(CryptoJS.enc.Base64)

  const decrypted = CryptoJS.AES.decrypt(cipher, CryptoJS.enc.Utf8.parse(t.key), {
    iv: CryptoJS.enc.Utf8.parse(t.iv),
    mode: CryptoJS.mode.CBC,
    padding: CryptoJS.pad.Pkcs7,
  })
  const decryptedStr = decrypted.toString(CryptoJS.enc.Utf8)

  golden.aes[t.name] = {
    mode: 'CBC',
    key: t.key,
    iv: t.iv,
    plaintext: t.plaintext,
    ciphertextBase64: base64,
    ciphertextBase64Alt: base64FromCiphertext,
    decrypted: decryptedStr,
    roundtripOk: decryptedStr === t.plaintext,
  }
}

// ============================================================
// 3. WEAPI vectors (deterministic via mockRandom)
// ============================================================

const weapiTests = [
  {
    name: 'login_cellphone',
    data: { phone: '13800138000', password: 'abc123', rememberLogin: 'true' },
  },
  {
    name: 'login_status',
    data: {},
  },
  {
    name: 'user_playlist',
    data: { uid: '12345', limit: '30', offset: '0' },
  },
  {
    name: 'recommend_songs',
    data: {},
  },
]

for (const test of weapiTests) {
  const text = JSON.stringify(test.data)

  // Layer 1: first AES-CBC encryption with presetKey → outputs base64 string
  // crypto.weapi() chains: aesEncrypt(aesEncrypt(text,'cbc',presetKey,iv), 'cbc', secretKey, iv)
  // aesEncrypt(text, mode, key, iv) — returns base64 when format defaults to 'base64'
  const layer1_base64 = crypto.aesEncrypt(text, 'cbc', '0CoJUm6Qyw8W8jud', '0102030405060708')

  // Build secretKey deterministically
  _seed = 12345
  Math.random = mockRandom
  const secretKeyChars = []
  for (let i = 0; i < 16; i++) {
    const idx = Math.round(mockRandom() * 61)
    secretKeyChars.push(BASE62[idx])
  }
  const secretKey = secretKeyChars.join('')
  Math.random = originalRandom

  // Layer 2: second AES-CBC encryption — encrypts the base64 STRING (as UTF-8) with secretKey
  const layer2_base64 = CryptoJS.AES.encrypt(
    CryptoJS.enc.Utf8.parse(layer1_base64),
    CryptoJS.enc.Utf8.parse(secretKey),
    { iv: CryptoJS.enc.Utf8.parse('0102030405060708'), mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7 },
  ).toString()

  // Full weapi result (with mocked random)
  const result = withMockedRandom(() => crypto.weapi(test.data))

  golden.weapi[test.name] = {
    data: test.data,
    plaintext: text,
    layer1_base64: layer1_base64,
    layer2_base64: layer2_base64,
    secretKey: secretKey,
    secretKeyReversed: secretKey.split('').reverse().join(''),
    params: result.params,
    paramsLength: result.params.length,
    encSecKey: result.encSecKey,
    encSecKeyLength: result.encSecKey.length,
    paramsMatchLayer2: result.params === layer2_base64,
  }
}

// ============================================================
// 4. RSA standalone vectors (deterministic — fixed input, no randomness)
// ============================================================

const forge = require('node-forge')
const rsaTestInputs = [
  '0123456789abcdef',
  'abcdefghijklmnop',
]

const forgePublicKey = forge.pki.publicKeyFromPem(RSA_PEM)

rsaTestInputs.forEach((input, idx) => {
  const encrypted = forgePublicKey.encrypt(input, 'NONE')
  const encHex = forge.util.bytesToHex(encrypted)

  golden.rsa[`fixed_${idx}`] = {
    input: input,
    inputLength: input.length,
    encryptedHex: encHex,
    encryptedLength: encHex.length,
    encryptedByteLength: encrypted.length,
  }
})

// ============================================================
// 5. Output
// ============================================================

const outDir = path.join(__dirname, '..', 'test')
if (!fs.existsSync(outDir)) {
  fs.mkdirSync(outDir, { recursive: true })
}
const outPath = path.join(outDir, 'golden_vectors.json')
fs.writeFileSync(outPath, JSON.stringify(golden, null, 2), 'utf-8')
console.log(`Golden vectors written to ${outPath}`)
console.log(`  eapi tests: ${Object.keys(golden.eapi).length}`)
console.log(`  weapi tests: ${Object.keys(golden.weapi).length}`)
console.log(`  aes tests: ${Object.keys(golden.aes).length}`)
console.log(`  rsa tests: ${Object.keys(golden.rsa).length}`)
