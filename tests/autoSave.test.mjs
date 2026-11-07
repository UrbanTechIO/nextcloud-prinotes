// Run with: node --test tests/autoSave.test.mjs
import { test, mock, afterEach } from 'node:test'
import assert from 'node:assert/strict'
import { createAutoSaver } from '../src/composables/autoSave.js'

const INTERVAL = 60_000
const settle = () => new Promise(resolve => setImmediate(resolve))

afterEach(() => mock.timers.reset())

test('saves once, 60 s after the first change, even while typing continues', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ } })
  s.markDirty()
  for (let i = 0; i < 5; i++) {
    mock.timers.tick(10_000)
    s.markDirty() // keeps typing: must NOT push the save back
  }
  await settle()
  assert.equal(saves, 0, '50 s in, nothing saved yet')
  mock.timers.tick(11_000)
  await settle()
  assert.equal(saves, 1)
  s.dispose()
})

test('a change after a save starts a new interval', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ } })
  s.markDirty()
  mock.timers.tick(INTERVAL)
  await settle()
  assert.equal(saves, 1)
  assert.equal(s.dirty(), false)
  s.markDirty()
  mock.timers.tick(59_000)
  await settle()
  assert.equal(saves, 1)
  mock.timers.tick(2_000)
  await settle()
  assert.equal(saves, 2)
  s.dispose()
})

test('nothing is saved while nothing changed', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ } })
  mock.timers.tick(5 * INTERVAL)
  await settle()
  assert.equal(saves, 0)
  s.dispose()
})

test('flush saves right away when dirty and cancels the pending timer', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ } })
  s.markDirty()
  await s.flush()
  assert.equal(saves, 1)
  assert.equal(s.dirty(), false)
  mock.timers.tick(2 * INTERVAL)
  await settle()
  assert.equal(saves, 1, 'the old timer must not save a second time')
  s.dispose()
})

test('flush does nothing when there is nothing unsaved', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ } })
  await s.flush()
  assert.equal(saves, 0)
  s.dispose()
})

test('an edit made while a save is running is saved by the next interval, not lost', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  let s
  s = createAutoSaver({
    interval: INTERVAL,
    save: async () => {
      saves++
      if (saves === 1) s.markDirty() // the user typed during the first save
    },
  })
  s.markDirty()
  mock.timers.tick(INTERVAL)
  await settle()
  assert.equal(saves, 1)
  assert.equal(s.dirty(), true)
  mock.timers.tick(INTERVAL)
  await settle()
  assert.equal(saves, 2)
  s.dispose()
})

test('a failed save stays unsaved and is retried at the next interval', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let calls = 0
  const s = createAutoSaver({
    interval: INTERVAL,
    save: async () => { calls++; if (calls === 1) throw new Error('offline') },
  })
  s.markDirty()
  mock.timers.tick(INTERVAL)
  await settle()
  assert.equal(calls, 1)
  assert.equal(s.dirty(), true)
  mock.timers.tick(INTERVAL)
  await settle()
  assert.equal(calls, 2)
  assert.equal(s.dirty(), false)
  s.dispose()
})

test('dispose cancels the timer without saving', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ } })
  s.markDirty()
  s.dispose()
  mock.timers.tick(2 * INTERVAL)
  await settle()
  assert.equal(saves, 0)
})

test('does not save when the note is back to what was last saved', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  let text = 'A'
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ }, snapshot: () => text })
  s.setBaseline()
  text = 'B'
  s.markDirty() // typed something...
  text = 'A' // ...then undid it
  mock.timers.tick(INTERVAL)
  await settle()
  assert.equal(saves, 0, 'nothing really changed, so the note must not be rewritten')
  assert.equal(s.dirty(), false)
  s.dispose()
})

test('flush also skips an identical note', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ }, snapshot: () => 'A' })
  s.setBaseline()
  s.markDirty()
  await s.flush()
  assert.equal(saves, 0)
  s.dispose()
})

test('saves a real change, and the saved version becomes the new baseline', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  let text = 'A'
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ }, snapshot: () => text })
  s.setBaseline()
  text = 'B'
  s.markDirty()
  mock.timers.tick(INTERVAL)
  await settle()
  assert.equal(saves, 1)
  text = 'A' // back to the ORIGINAL text, which is now a real change from what is saved
  s.markDirty()
  mock.timers.tick(INTERVAL)
  await settle()
  assert.equal(saves, 2)
  s.dispose()
})

test('without a baseline the first save always happens', async () => {
  mock.timers.enable({ apis: ['setTimeout'] })
  let saves = 0
  const s = createAutoSaver({ interval: INTERVAL, save: async () => { saves++ }, snapshot: () => 'A' })
  s.markDirty()
  await s.flush()
  assert.equal(saves, 1)
  s.dispose()
})
