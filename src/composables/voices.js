/**
 * Voice recordings in a note, shared with the Android app:
 *   "voices": { "<id>": { "label": "Voice note 09:05", "duration": 4200, "mime": "audio/mp4" } }
 * and in the text an embed `{ "voice": "<id>" }`. The audio itself is a separate file on the server
 * (PriNotes/voice in the user's Files), fetched by id.
 */

const two = (n) => String(n).padStart(2, '0')

/** 4200 becomes "0:04", 65000 becomes "1:05". */
export function formatLength(ms) {
  const s = Math.floor((Number(ms) || 0) / 1000)
  return `${Math.floor(s / 60)}:${two(s % 60)}`
}

/** The ids of the recordings that are in the text. */
export function voiceIdsInDelta(ops) {
  const ids = new Set()
  for (const op of ops || []) {
    if (op && op.insert && typeof op.insert === 'object' && op.insert.voice) ids.add(op.insert.voice)
  }
  return ids
}

/** What a new recording is saved as in the note. */
export function newVoiceMeta({ durationMs, mime, at = new Date(), wave }) {
  const meta = { label: `Voice note ${two(at.getHours())}:${two(at.getMinutes())}`, duration: durationMs, mime }
  if (Array.isArray(wave) && wave.length) meta.wave = wave
  return meta
}

/** How many bars a recording is drawn with. */
export const WAVE_BARS = 60

/**
 * Turns the loudness readings taken while recording (0 to 1) into 60 numbers from 0 to 100, saved in the note.
 * The loudest part always reaches the top, so a quiet recording still shows its shape; silence stays low.
 * Same rule as the phone, so a recording looks the same on both.
 */
export function resampleWave(levels, bars = WAVE_BARS) {
  const n = levels.length
  if (!n) return []
  const means = []
  for (let i = 0; i < bars; i++) {
    const from = Math.min(n - 1, Math.floor((i * n) / bars))
    const to = Math.min(n, Math.max(from + 1, Math.ceil(((i + 1) * n) / bars)))
    let sum = 0
    let peak = 0
    for (let j = from; j < to; j++) {
      sum += levels[j]
      peak = Math.max(peak, levels[j])
    }
    means.push((sum / (to - from)) * 0.5 + peak * 0.5)
  }
  const scale = 1 / Math.max(Math.max(...means), 0.25)
  return means.map((m) => Math.max(0, Math.min(100, Math.round(m * scale * 100))))
}

/** The bars of a recording as 0 to 1. One made before waves existed shows a flat row (its shape is not known). */
export function barsToShow(meta, bars = WAVE_BARS) {
  const w = meta && meta.wave
  if (Array.isArray(w) && w.length && w.every((v) => typeof v === 'number')) {
    return w.map((v) => Math.max(0, Math.min(100, v)) / 100)
  }
  return new Array(bars).fill(0.3)
}

/** Adds the newest level to the live bars and drops the oldest, keeping at most [max]. */
export function pushLevel(live, level, max = 48) {
  const next = [...live, level]
  return next.length > max ? next.slice(next.length - max) : next
}

/**
 * Where a dragged recording lands. [blocks] are the top and bottom (page y) of the other blocks in the note,
 * top to bottom; [y] is where the finger is. Gives the block and whether to go after it (below its middle).
 */
export function dropIndexFor(blocks, y) {
  if (!blocks.length) return null
  if (y < blocks[0].top) return { block: 0, after: false }
  const last = blocks.length - 1
  if (y > blocks[last].bottom) return { block: last, after: true }
  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i]
    if (y >= b.top && y <= b.bottom) return { block: i, after: y > (b.top + b.bottom) / 2 }
  }
  // between two blocks (a margin): the next one down
  for (let i = 0; i < blocks.length; i++) if (blocks[i].top > y) return { block: i, after: false }
  return { block: last, after: true }
}

/** The first recording type the browser can make (the phone plays all of them). '' when it can make none. */
export function pickRecordingType(isSupported) {
  const candidates = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus', 'audio/ogg']
  return candidates.find((t) => isSupported(t)) || ''
}

/** The file name for an upload: the id plus the ending that matches the type. */
export function voiceFilename(id, mime) {
  const base = String(mime || '').split(';')[0].trim().toLowerCase()
  const ext = base.includes('webm') ? 'webm' : base.includes('ogg') ? 'ogg' : base.includes('mpeg') ? 'mp3' : 'm4a'
  return `${id}.${ext}`
}

/** A random id in the same form the phone uses (a version 4 uuid). */
export function uuid() {
  const bytes = new Uint8Array(16)
  globalThis.crypto.getRandomValues(bytes)
  bytes[6] = (bytes[6] & 0x0f) | 0x40
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  const h = [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}
