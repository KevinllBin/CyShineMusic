const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');

const preload = fs.readFileSync('android/app/src/main/assets/music_source_preload.js', 'utf8');

function runtime() {
  const events = [];
  const unused = () => { throw new Error('Unexpected native helper'); };
  const context = vm.createContext({
    __music_source_native_call__: (action, data) => events.push({ action, data: JSON.parse(data) }),
    __music_source_md5__: unused,
    __music_source_bytes_to_b64__: unused,
    __music_source_b64_to_bytes__: unused,
    __music_source_aes_encrypt__: unused,
    __music_source_rsa_encrypt__: unused,
    __music_source_set_timeout__: unused,
    __music_source_clear_timeout__: unused,
  });
  vm.runInContext(preload, context);
  context.music_source_setup('{}');
  return { context, events };
}

test('initialization retains Qishui and filters only unsupported qualities and platforms', () => {
  const { context, events } = runtime();
  vm.runInContext(`lx.send('inited', { sources: {
    qs: { type: 'music', actions: ['musicUrl'], qualitys: ['32k','64k','128k','256k','320k','flac'] },
    kw: { type: 'music', actions: ['musicUrl'], qualitys: ['128k'] },
    other: { type: 'music', actions: ['musicUrl'], qualitys: ['128k'] },
  } })`, context);
  assert.equal(events[0].data.status, true);
  assert.deepEqual(events[0].data.info.sources.qs, {
    type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k', 'flac'],
  });
  assert.deepEqual(Object.keys(events[0].data.info.sources), ['qs', 'kw']);
});

test('resolution passes qs and a string songmid unchanged to the source', async () => {
  const { context, events } = runtime();
  vm.runInContext(`lx.on('request', ({source, action, info}) => {
    if (source !== 'qs' || action !== 'musicUrl' || info.type !== '320k' ||
        info.musicInfo.songmid !== '6778775242320906241') throw new Error('Incorrect source arguments');
    return Promise.resolve('https://audio.example.test/qishui.m4a');
  })`, context);
  context.__music_source_handle__('resolve', JSON.stringify({
    requestId: 'qs-test', source: 'qs', quality: '320k',
    musicInfo: { songmid: '6778775242320906241' },
  }));
  await new Promise(resolve => setImmediate(resolve));
  const result = events.find(event => event.action === 'resolveResult').data;
  assert.equal(result.status, true);
  assert.equal(result.url, 'https://audio.example.test/qishui.m4a');
});
