/**
 * Builds the saved note JSON (`quill-1.0`, the same shape the Android app writes).
 * Images no longer referenced by the text are dropped. Drawing strokes made on the phone are passed
 * through untouched: the web editor does not edit them, but it must never lose them.
 */
export function buildNoteJson({ delta, images, strokes, strokesWidth }) {
  const referenced = new Set()
  for (const op of delta || []) {
    if (op.insert && typeof op.insert === 'object' && op.insert.image) referenced.add(op.insert.image)
  }
  const cleaned = {}
  for (const [k, v] of Object.entries(images || {})) {
    if (referenced.has(k)) cleaned[k] = v
  }
  const out = {
    version: 'quill-1.0',
    delta,
    images: cleaned,
    strokes: Array.isArray(strokes) ? strokes : [],
  }
  if (Number.isFinite(strokesWidth) && strokesWidth > 0) out.strokesWidth = strokesWidth
  return JSON.stringify(out)
}
