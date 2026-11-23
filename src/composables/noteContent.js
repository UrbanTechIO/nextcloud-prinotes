/**
 * Builds the saved note JSON (`quill-1.0`, the same shape the Android app writes).
 * Images no longer referenced by the text are dropped, and so are voice recordings no longer in the text.
 * Drawing strokes made on the phone are passed through untouched: the web editor does not edit them, but it
 * must never lose them.
 */
export function buildNoteJson({ delta, images, strokes, strokesWidth, voices }) {
  const referenced = new Set()
  const voiceRefs = new Set()
  for (const op of delta || []) {
    if (op.insert && typeof op.insert === 'object') {
      if (op.insert.image) referenced.add(op.insert.image)
      if (op.insert.voice) voiceRefs.add(op.insert.voice)
    }
  }
  const cleaned = {}
  for (const [k, v] of Object.entries(images || {})) {
    if (referenced.has(k)) cleaned[k] = v
  }
  const keptVoices = {}
  for (const [k, v] of Object.entries(voices || {})) {
    if (voiceRefs.has(k)) keptVoices[k] = v
  }
  const out = {
    version: 'quill-1.0',
    delta,
    images: cleaned,
    strokes: Array.isArray(strokes) ? strokes : [],
  }
  if (Object.keys(keptVoices).length) out.voices = keptVoices
  if (Number.isFinite(strokesWidth) && strokesWidth > 0) out.strokesWidth = strokesWidth
  return JSON.stringify(out)
}
