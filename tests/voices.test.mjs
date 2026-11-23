// Run with: node --test tests/voices.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { formatLength, voiceIdsInDelta, newVoiceMeta, pickRecordingType, voiceFilename, uuid } from '../src/composables/voices.js'
import { buildNoteJson } from '../src/composables/noteContent.js'

test('lengths are shown as minutes and seconds', () => {
  assert.equal(formatLength(0), '0:00')
  assert.equal(formatLength(4200), '0:04')
  assert.equal(formatLength(65000), '1:05')
  assert.equal(formatLength(3725000), '62:05')
  assert.equal(formatLength(undefined), '0:00')
})

test('the recordings in the text are found in the delta', () => {
  const ops = [
    { insert: 'hi\n' },
    { insert: { voice: 'aaaaaaaa-1' } },
    { insert: '\n' },
    { insert: { image: 'img_1' } },
    { insert: { voice: 'bbbbbbbb-2' } },
  ]
  assert.deepEqual([...voiceIdsInDelta(ops)], ['aaaaaaaa-1', 'bbbbbbbb-2'])
  assert.deepEqual([...voiceIdsInDelta([])], [])
  assert.deepEqual([...voiceIdsInDelta(undefined)], [])
})

test('a new recording gets a label with the time, its length and its type', () => {
  const meta = newVoiceMeta({ durationMs: 4200, mime: 'audio/webm', at: new Date(2026, 10, 23, 9, 5) })
  assert.deepEqual(meta, { label: 'Voice note 09:05', duration: 4200, mime: 'audio/webm' })
})

test('the browser picks a recording type it can make and the phone can play', () => {
  const only = (...ok) => (t) => ok.includes(t)
  assert.equal(pickRecordingType(only('audio/webm;codecs=opus', 'audio/webm')), 'audio/webm;codecs=opus')
  assert.equal(pickRecordingType(only('audio/mp4')), 'audio/mp4')
  assert.equal(pickRecordingType(only('audio/ogg;codecs=opus')), 'audio/ogg;codecs=opus')
  assert.equal(pickRecordingType(() => false), '')
})

test('the file name carries the right ending for the type', () => {
  assert.equal(voiceFilename('aaaaaaaa-1', 'audio/webm;codecs=opus'), 'aaaaaaaa-1.webm')
  assert.equal(voiceFilename('aaaaaaaa-1', 'audio/mp4'), 'aaaaaaaa-1.m4a')
  assert.equal(voiceFilename('aaaaaaaa-1', 'audio/ogg'), 'aaaaaaaa-1.ogg')
  assert.equal(voiceFilename('aaaaaaaa-1', 'audio/mpeg'), 'aaaaaaaa-1.mp3')
  assert.equal(voiceFilename('aaaaaaaa-1', ''), 'aaaaaaaa-1.m4a')
})

test('ids look like the ones the phone makes', () => {
  const id = uuid()
  assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
  assert.notEqual(id, uuid())
})

test('saving keeps the recordings that are in the text and drops the rest', () => {
  const json = JSON.parse(buildNoteJson({
    delta: [{ insert: 'x\n' }, { insert: { voice: 'aaaaaaaa-1' } }, { insert: '\n' }],
    images: {},
    strokes: [],
    voices: {
      'aaaaaaaa-1': { label: 'One', duration: 1000, mime: 'audio/mp4' },
      'bbbbbbbb-2': { label: 'Gone', duration: 2000, mime: 'audio/mp4' },
    },
  }))
  assert.deepEqual(Object.keys(json.voices), ['aaaaaaaa-1'])
  assert.equal(json.voices['aaaaaaaa-1'].label, 'One')
})

test('a note without recordings has no voices field', () => {
  const json = JSON.parse(buildNoteJson({ delta: [{ insert: 'x\n' }], images: {}, strokes: [], voices: { 'bbbbbbbb-2': { label: 'Gone' } } }))
  assert.equal('voices' in json, false)
  const json2 = JSON.parse(buildNoteJson({ delta: [{ insert: 'x\n' }], images: {}, strokes: [] }))
  assert.equal('voices' in json2, false)
})

import { resampleWave, barsToShow, pushLevel, dropIndexFor } from '../src/composables/voices.js'

test('a recording becomes 60 bars from 0 to 100, and its loudest part reaches the top', () => {
  const levels = Array.from({ length: 500 }, (_, i) => (i % 50) / 50)
  const w = resampleWave(levels)
  assert.equal(w.length, 60)
  assert.ok(w.every((v) => v >= 0 && v <= 100))
  const quiet = resampleWave(new Array(200).fill(0.3))
  assert.ok(Math.max(...quiet) >= 90)
})

test('silence stays low and loud-then-quiet keeps its order', () => {
  assert.ok(Math.max(...resampleWave(new Array(200).fill(0.01))) < 10)
  const w = resampleWave([...new Array(100).fill(0.9), ...new Array(100).fill(0.1)])
  assert.ok(w[5] > 60 && w[55] < 40 && w[0] > w[59])
})

test('a short recording still fills every bar, and nothing recorded gives none', () => {
  assert.equal(resampleWave([0.2, 0.8, 0.5]).length, 60)
  assert.deepEqual(resampleWave([]), [])
})

test('saved bars are shown as they are; old recordings get a flat row', () => {
  assert.deepEqual(barsToShow({ wave: [0, 50, 100] }), [0, 0.5, 1])
  const flat = barsToShow({ label: 'old' })
  assert.equal(flat.length, 60)
  assert.equal(new Set(flat).size, 1)
  assert.equal(barsToShow({ wave: 'nope' }).length, 60)
  assert.equal(barsToShow({ wave: [] }).length, 60)
})

test('the live bars keep the newest on the right and drop the oldest', () => {
  let live = []
  for (let i = 1; i <= 5; i++) live = pushLevel(live, i / 10, 3)
  assert.deepEqual(live, [0.3, 0.4, 0.5])
})

test('a new recording saves its bars, and has no wave field without them', () => {
  assert.deepEqual(newVoiceMeta({ durationMs: 1000, mime: 'audio/webm', at: new Date(2026, 10, 23, 9, 5), wave: [1, 2, 3] }).wave, [1, 2, 3])
  assert.equal('wave' in newVoiceMeta({ durationMs: 1000, mime: 'audio/webm' }), false)
})

test('dropping a recording: where it goes among the blocks', () => {
  // blocks (top, bottom): A 0-40, B 40-100, C 100-140 ; the finger is at y
  const blocks = [{ top: 0, bottom: 40 }, { top: 40, bottom: 100 }, { top: 100, bottom: 140 }]
  assert.deepEqual(dropIndexFor(blocks, 10), { block: 0, after: false })
  assert.deepEqual(dropIndexFor(blocks, 35), { block: 0, after: true })
  assert.deepEqual(dropIndexFor(blocks, 90), { block: 1, after: true })
  assert.deepEqual(dropIndexFor(blocks, 120), { block: 2, after: false })
  assert.deepEqual(dropIndexFor(blocks, 500), { block: 2, after: true })
  assert.deepEqual(dropIndexFor(blocks, -50), { block: 0, after: false })
  assert.equal(dropIndexFor([], 10), null)
})
