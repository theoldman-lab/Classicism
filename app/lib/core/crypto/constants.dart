import 'dart:typed_data';

// ============================================================
// AES Constants
// ============================================================

const iv = '0102030405060708';
const presetKey = '0CoJUm6Qyw8W8jud';
const eapiKey = 'e82ckenh8dichen8';
const linuxapiKey = 'rFgB&h#%2?^eDg:Q';

// ============================================================
// RSA Public Key (1024-bit, PEM)
// ============================================================

const rsaPublicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB
-----END PUBLIC KEY-----''';

// ============================================================
// XEAPI Constants
// ============================================================

final xeapiStaticKey = Uint8List.fromList([
  0xab, 0x1d, 0x5a, 0x43, 0x0f, 0x6b, 0xb0, 0x4a,
  0x3f, 0x01, 0xe8, 0x1d, 0xdd, 0x72, 0xbd, 0x91,
  0x6d, 0x5c, 0xe5, 0x91, 0x24, 0x8a, 0xc1, 0x28,
  0x71, 0x48, 0x06, 0xd7, 0xf8, 0xfb, 0x1b, 0x84,
]);

const xeapiSignKey =
    'mUHCwVNWJbunMqAHf5MImuirT6plvs6VSFW62MGHstFQxhBGdEoIhLItH3djc4+FB/OKty3+lL2rGeoFBpVe5g==';

final x25519SpkiPrefix = Uint8List.fromList([
  0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00,
]);

// ============================================================
// Base62 Alphabet
// ============================================================

const base62Alphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

// ============================================================
// EAPI Protocol Constants
// ============================================================

const eapiDelimiter = '-36cd479b6b5-';

// ============================================================
// API Domains
// ============================================================

const apiDomain = 'https://interface.music.163.com';
const xeapiDomain = 'https://interface3.music.163.com';
const domain = 'https://music.163.com';
const clDomain = 'https://clientlog.music.163.com';
const clDomain3 = 'https://clientlog3.music.163.com';

// ============================================================
// Resource Type Map (for constructing resource IDs)
// ============================================================

const resourceTypeMap = <String, String>{
  '0': 'R_SO_4_',
  '1': 'R_MV_5_',
  '2': 'A_PL_0_',
  '3': 'R_AL_3_',
  '4': 'A_DJ_1_',
  '5': 'R_VI_62_',
  '6': 'A_EV_2_',
  '7': 'A_DR_14_',
};

// ============================================================
// Client Sign & Check Token
// ============================================================

const clientSign =
    '18:C0:4D:B9:8F:FE@@@453832335F384641365F424635335F303030315F303031425F343434415F343643365F333638332@@@@@@6ff673ef74955b38bce2fa8562d95c976ed4758b1227c4e9ee345987cee17bc9';
const checkToken =
    '9ca17ae2e6ffcda170e2e6ee8af14fbabdb988f225b3868eb2c15a879b9a83d274a790ac8ff54a97b889d5d42af0feaec3b92af58cff99c470a7eafd88f75e839a9ea7c14e909da883e83fb692a3abdb6b92adee9e';

// ============================================================
// Device Fingerprint Defaults
// ============================================================

// These match osMap['android'] and eapi header defaults from util/request.js
const defaultPlatform = 'android';
const defaultOsver = '14';
const defaultAppver = '8.20.20.231215173437';
const defaultVersioncode = '140';
const defaultMobileName = '';
const defaultResolution = '1920x1080';
const defaultChannel = 'xiaomi';

// ============================================================
// Encryption Scheme Enum
// ============================================================

enum Crypto {
  weapi,
  eapi,
  xeapi,
  api,
  linuxapi,
}
