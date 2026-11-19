<template>
  <div class="prinotes-quill-wrapper">
    <!-- Toolbar (Quill binds by CSS ID) -->
    <div :id="'ql-toolbar-' + uid" class="ql-toolbar-row">
      <span class="ql-formats">
        <button type="button" class="pn-undo" title="Undo (Ctrl+Z)" aria-label="Undo" :disabled="!canUndo" @click="undo">↶</button>
        <button type="button" class="pn-redo" title="Redo (Ctrl+Y)" aria-label="Redo" :disabled="!canRedo" @click="redo">↷</button>
      </span>
      <span class="ql-formats">
        <select class="ql-header" title="Text style">
          <option value="1">H1</option>
          <option value="2">H2</option>
          <option value="3">H3</option>
          <option selected>P</option>
        </select>
        <select class="ql-size ql-prinotes-size" title="Font size">
          <option selected></option>
          <option value="12">12</option>
          <option value="15">15</option>
          <option value="18">18</option>
          <option value="22">22</option>
          <option value="28">28</option>
        </select>
      </span>
      <span class="ql-formats">
        <button class="ql-bold" title="Bold" />
        <button class="ql-italic" title="Italic" />
        <button class="ql-underline" title="Underline" />
        <button class="ql-strike" title="Strike" />
      </span>
      <span class="ql-formats">
        <select class="ql-color" title="Text colour" />
        <select class="ql-background" title="Highlight" />
      </span>
      <span class="ql-formats">
        <button class="ql-list" value="ordered" title="Numbered list" />
        <button class="ql-list" value="bullet" title="Bullet list" />
        <button class="ql-list" value="unchecked" title="Checklist" />
      </span>
      <span class="ql-formats">
        <button class="ql-blockquote" title="Quote" />
        <button class="ql-code-block" title="Code" />
        <button class="ql-link" title="Link" />
      </span>
      <span class="ql-formats">
        <button class="ql-clean" title="Clear formatting" />
      </span>
      <span class="ql-formats">
        <button class="ql-image" title="Insert image" @click="onInsertImage" />
        <button class="ql-prinotes-draw" :class="{ 'pn-active': drawMode }" title="Draw on the page" aria-label="Draw on the page" @click="toggleDraw">✎</button>
        <button class="ql-prinotes-divider" title="Insert divider" @click="onInsertDivider">—</button>
      </span>
    </div>

    <!-- Drawing tools: the strokes are saved exactly like the phone saves them -->
    <div v-if="drawMode" class="draw-bar">
      <button type="button" :class="{ on: !eraser }" @click="eraser = false">Pen</button>
      <button type="button" :class="{ on: eraser }" @click="eraser = true">Eraser</button>
      <input v-model="penColor" type="color" :disabled="eraser" aria-label="Pen colour" @input="penColorTouched = true" />
      <input v-model.number="penWidth" type="range" min="1" max="24" aria-label="Pen size" />
      <span class="draw-size">{{ penWidth }}</span>
      <button type="button" :disabled="!strokeCount" @click="undoStroke">Undo</button>
      <button type="button" :disabled="!strokeCount" @click="clearStrokes">Clear</button>
      <button type="button" class="done" @click="toggleDraw">Done</button>
    </div>

    <!-- Quill target -->
    <div class="ql-stage">
      <div :id="'ql-container-' + uid" class="ql-target" />
      <!-- Freehand drawings made in the Android app, drawn over the text -->
      <canvas
        ref="strokeCanvas"
        class="stroke-layer"
        :class="{ drawing: drawMode }"
        aria-hidden="true"
        @pointerdown="onPointerDown"
        @pointermove="onPointerMove"
        @pointerup="onPointerUp"
        @pointercancel="onPointerUp"
        @wheel.prevent="onWheel"
      />
    </div>

    <!-- Hidden file input for image picker -->
    <input ref="fileInput" type="file" accept="image/*" style="display:none" @change="onImagePicked" />

  </div>
</template>

<script setup>
/**
 * QuillEditor.vue
 * ───────────────
 *  Real Quill 2.x instance for the web side. Reads/writes the same
 *  `quill-1.0` delta shape used by the Android app (flutter_quill).
 *
 *  Data model (unchanged from Android):
 *    {
 *      version: 'quill-1.0',
 *      delta:   [...Quill delta ops...],
 *      images:  { key: { data: 'data:image/...', width, height, rotation } },
 *      strokes: [...]   // freehand drawing from the Android app: drawn over the text and kept on save
 *      strokesWidth     // page width (Android units) the drawing was made on
 *    }
 *
 *  Custom pieces registered with Quill:
 *    - Numeric font-size format matching flutter_quill values
 *      (12 / 15 / 18 / 22 / 28 px), so a size set on either platform
 *      renders on the other.
 *    - ImageBlot   — the delta stores `{image: 'imgN'}` keys; the blot
 *      resolves the key against a live per-instance images map and
 *      renders an <img>. Keeps the delta small and matches the mobile
 *      encoding exactly.
 *    - DividerBlot — `{divider: true}` embed rendered as <hr>.
 *
 *  Legacy formats:
 *    - v2.0 paragraph format is migrated to quill-1.0 on load.
 *    - Anything else (plain text, markdown) falls through as plain lines.
 *
 *  Emits update:modelValue with the JSON string (same shape as before,
 *  so no store/API changes required).
 */
import { ref, onMounted, onBeforeUnmount, watch, nextTick } from 'vue'
import Quill from 'quill'
import 'quill/dist/quill.snow.css'
import { drawStrokes, referenceWidth, strokesBottom, parseRgb, rgbToHex, toReferencePoint, makeStroke, nextStrokesWidth } from '../../composables/strokes'
import { buildNoteJson } from '../../composables/noteContent'
import { FONT_SIZES, toPxSize, fromPxSize } from '../../composables/fontSize'

const props = defineProps({
  modelValue: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue', 'ready'])

const uid = Math.random().toString(36).slice(2, 10)
let quill = null
let internalUpdate = false     // set while WE mutate the doc, so text-change doesn't re-emit
let imagesMap = {}             // key -> { data, width, height, rotation }
let imgCounter = 0
let strokesData = []           // Android freehand strokes: shown and preserved, never edited here
let strokesWidth = 0           // page width those strokes were drawn on (0 = unknown)
let strokeObserver = null
const strokeCanvas = ref(null)

// Drawing mode: freehand strokes saved the same way the Android app saves them.
const drawMode = ref(false)
const eraser = ref(false)
const penColor = ref('#000000')
let penColorTouched = false      // the user picked a colour themselves: keep it
const penWidth = ref(4)
const strokeCount = ref(0)
let liveStroke = null           // the stroke being drawn right now: { points }
const fileInput = ref(null)

// ── Custom formats / blots ────────────────────────────────────────────────
// Registered once per module load; the flags below prevent double-registration
// on hot-reload / navigation.
if (!Quill.__prinotesRegistered) {
  Quill.__prinotesRegistered = true

  // Numeric px font size — accept exactly the sizes the mobile toolbar uses.
  // The phone stores "28", the CSS needs "28px": this format reads and writes the phone's form, and still
  // accepts "28px" from notes saved by older web versions.
  const Parchment = Quill.import('parchment')
  class PhoneSizeStyle extends Parchment.StyleAttributor {
    canAdd(node, value) { return super.canAdd(node, toPxSize(value)) }
    add(node, value) { return super.add(node, toPxSize(value)) }
    value(node) { return fromPxSize(super.value(node)) }
  }
  Quill.register(
    new PhoneSizeStyle('size', 'font-size', {
      scope: Parchment.Scope.INLINE,
      whitelist: FONT_SIZES.map((n) => `${n}px`),
    }),
    true,
  )

  // Explicit alignments (right/center/justify) so they round-trip if mobile
  // ever adds them.
  const AlignStyle = Quill.import('attributors/style/align')
  Quill.register(AlignStyle, true)

  // ImageBlot — renders <img> whose src comes from a per-Quill-instance
  // images map. Delta stays as {image: 'imgN'}, matching flutter_quill.
  const BlockEmbed = Quill.import('blots/block/embed')
  class PriNotesImageBlot extends BlockEmbed {
    static create(key) {
      const node = super.create()
      node.setAttribute('data-key', key)
      node.classList.add('prinotes-image-embed')
      // The actual <img> is stamped in by refreshImageDom() — the blot
      // itself keeps only the key so serialize() reads it back cleanly.
      return node
    }
    static value(node) { return node.getAttribute('data-key') }
  }
  PriNotesImageBlot.blotName = 'image'
  PriNotesImageBlot.tagName = 'div'
  Quill.register(PriNotesImageBlot, true)

  // Divider embed
  class PriNotesDividerBlot extends BlockEmbed {
    static create() {
      const node = super.create()
      node.classList.add('prinotes-divider-embed')
      return node
    }
    static value() { return true }
  }
  PriNotesDividerBlot.blotName = 'divider'
  PriNotesDividerBlot.tagName = 'hr'
  Quill.register(PriNotesDividerBlot, true)
}

// ── Content parsing (input) ───────────────────────────────────────────────
function parseIncoming(raw) {
  const out = { delta: [], images: {}, strokes: [], strokesWidth: 0 }
  if (!raw) return out
  try {
    const parsed = JSON.parse(raw)
    if (parsed.version === 'quill-1.0') {
      out.delta   = Array.isArray(parsed.delta) ? parsed.delta : []
      out.images  = parsed.images  ?? {}
      out.strokes = parsed.strokes ?? []
      out.strokesWidth = Number(parsed.strokesWidth) || 0
      return out
    }
    if (parsed.version === '2.0') return migrateV2(parsed)
    // Legacy v1.0 web-blocks (before Android existed) — best-effort
    if (Array.isArray(parsed.blocks)) return migrateWebBlocks(parsed)
  } catch {
    // Not JSON — treat as plain text
    out.delta = [{ insert: raw + '\n' }]
    return out
  }
  return out
}

function migrateV2(parsed) {
  const ops = []
  for (const p of (parsed.paragraphs ?? [])) {
    const style = p.style || 'normal'
    const text  = p.text || ''
    if (text) ops.push({ insert: text })
    if      (style === 'h1')        ops.push({ insert: '\n', attributes: { header: 1 } })
    else if (style === 'h2')        ops.push({ insert: '\n', attributes: { header: 2 } })
    else if (style === 'h3')        ops.push({ insert: '\n', attributes: { header: 3 } })
    else if (style === 'bullet')    ops.push({ insert: '\n', attributes: { list: 'bullet' } })
    else if (style === 'numbered')  ops.push({ insert: '\n', attributes: { list: 'ordered' } })
    else if (style === 'checklist') ops.push({ insert: '\n', attributes: { list: p.checked ? 'checked' : 'unchecked' } })
    else                            ops.push({ insert: '\n' })
  }
  const images = {}
  let idx = 0
  for (const img of (parsed.images ?? [])) {
    const key = `img_${idx++}`
    images[key] = { data: img.data || '', width: img.width ?? null, height: img.height ?? null, rotation: img.rotation ?? 0 }
    ops.push({ insert: { image: key } })
    ops.push({ insert: '\n' })
  }
  return { delta: ops, images, strokes: parsed.strokes ?? [], strokesWidth: Number(parsed.strokesWidth) || 0 }
}

function migrateWebBlocks(parsed) {
  // Very old web-only format (no Android). Best-effort: dump plain text.
  const ops = []
  for (const b of (parsed.blocks ?? [])) {
    if (b.content) {
      const text = b.content.map(s => (s.text ?? s.insert ?? '')).join('')
      if (text) ops.push({ insert: text })
      ops.push({ insert: '\n' })
    } else if (b.items) {
      for (const it of b.items) {
        if (it.text) ops.push({ insert: it.text })
        ops.push({ insert: '\n', attributes: { list: b.type === 'checklist'
          ? (it.checked ? 'checked' : 'unchecked')
          : (b.ordered ? 'ordered' : 'bullet') } })
      }
    } else if (b.type === 'code') {
      const lines = (b.code ?? '').split('\n')
      for (const line of lines) {
        if (line) ops.push({ insert: line })
        ops.push({ insert: '\n', attributes: { 'code-block': true } })
      }
    } else if (b.type === 'divider') {
      ops.push({ insert: { divider: true } })
      ops.push({ insert: '\n' })
    }
  }
  return { delta: ops, images: {}, strokes: [] }
}

// ── Content serialization (output) ────────────────────────────────────────
function serialize() {
  if (!quill) return props.modelValue
  return buildNoteJson({
    delta: quill.getContents().ops,
    images: imagesMap,
    strokes: strokesData,
    strokesWidth,
  })
}

// ── Android freehand drawing layer ────────────────────────────────────────
function scrollHost() {
  return document.getElementById(`ql-container-${uid}`)
}

/** The page's background and text colours, so ink that would vanish on it can be shown readably. */
function pageColors(host) {
  let bg = [255, 255, 255]
  for (let el = host; el; el = el.parentElement) {
    const c = parseRgb(getComputedStyle(el).backgroundColor)
    if (c && c[3] > 0.5) {
      bg = [c[0], c[1], c[2]]
      break
    }
  }
  const t = quill ? parseRgb(getComputedStyle(quill.root).color) : null
  const fg = t ? [t[0], t[1], t[2]] : (bg[0] + bg[1] + bg[2] > 382 ? [30, 30, 30] : [235, 235, 235])
  return { background: bg, foreground: fg }
}

/** Draws the strokes over the visible part of the editor, scaled to its width. */
function redrawStrokes() {
  const canvas = strokeCanvas.value
  const host = scrollHost()
  if (!canvas || !host) return
  const w = host.clientWidth
  const h = host.clientHeight
  const dpr = window.devicePixelRatio || 1
  canvas.style.left = (host.offsetLeft + host.clientLeft) + 'px'
  canvas.style.top = (host.offsetTop + host.clientTop) + 'px'
  if (canvas.style.width !== w + 'px' || canvas.style.height !== h + 'px') {
    canvas.width = Math.round(w * dpr)
    canvas.height = Math.round(h * dpr)
    canvas.style.width = w + 'px'
    canvas.style.height = h + 'px'
  }
  const ctx = canvas.getContext('2d')
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  ctx.clearRect(0, 0, w, h)
  const live = currentLive()
  if ((!strokesData.length && !live) || !w) return
  const scale = w / referenceWidth(strokesData, strokesWidth)
  drawStrokes(ctx, live ? [...strokesData, live] : strokesData, { scale, offsetY: host.scrollTop, ...pageColors(host) })
}

/** Makes the page tall enough that the lowest part of the drawing can be scrolled to. */
function fitEditorToStrokes() {
  const host = scrollHost()
  if (!quill || !host) return
  if (!strokesData.length || !host.clientWidth) {
    quill.root.style.minHeight = ''
    return
  }
  const scale = host.clientWidth / referenceWidth(strokesData, strokesWidth)
  quill.root.style.minHeight = Math.max(300, Math.ceil(strokesBottom(strokesData) * scale + 24)) + 'px'
}

function refreshStrokes() {
  fitEditorToStrokes()
  redrawStrokes()
}

// ── Rendering image embeds ────────────────────────────────────────────────
// The blot only carries the key; we walk the DOM and paint the real <img>
// after every content change.
function refreshImageDom() {
  if (!quill) return
  const nodes = quill.root.querySelectorAll('div.prinotes-image-embed')
  nodes.forEach(node => {
    const key = node.getAttribute('data-key')
    const meta = imagesMap[key]
    if (!meta || !meta.data) {
      node.innerHTML = '<div class="prinotes-image-missing">missing image</div>'
      return
    }
    // Only replace if the img isn't already there for this key (avoid churn)
    if (node.firstElementChild?.tagName === 'IMG' &&
        node.firstElementChild.getAttribute('data-key') === key) return
    const rotationDeg = (meta.rotation || 0) * 180 / Math.PI
    const w = meta.width ? `${meta.width}px` : '100%'
    node.innerHTML =
      `<img src="${escapeAttr(meta.data)}" data-key="${escapeAttr(key)}" ` +
      `style="max-width:100%;width:${w};height:auto;transform:rotate(${rotationDeg}deg);transform-origin:center center;" ` +
      `draggable="false" />`
  })
}
function escapeAttr(s) {
  return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;')
}

// ── Insert helpers ────────────────────────────────────────────────────────
function onInsertImage() { fileInput.value?.click() }

function onImagePicked(event) {
  const file = event.target.files?.[0]
  event.target.value = ''
  if (!file) return
  const reader = new FileReader()
  reader.onload = e => {
    const key = `img_${Date.now()}_${imgCounter++}`
    imagesMap[key] = { data: e.target.result, width: null, height: null, rotation: 0 }
    const range = quill.getSelection(true)
    quill.insertEmbed(range.index, 'image', key, Quill.sources.USER)
    quill.setSelection(range.index + 1, 0, Quill.sources.SILENT)
    // refreshImageDom happens on the text-change that Quill fires
  }
  reader.readAsDataURL(file)
}

function onInsertDivider() {
  const range = quill.getSelection(true)
  quill.insertEmbed(range.index, 'divider', true, Quill.sources.USER)
  quill.setSelection(range.index + 1, 0, Quill.sources.SILENT)
}

/** Switches the page between writing and drawing. While drawing, typing is off and the pointer draws. */
function toggleDraw() {
  drawMode.value = !drawMode.value
  if (!quill) return
  quill.enable(!drawMode.value)
  if (drawMode.value) {
    quill.blur()
    // Start in the page's own text colour (white on a dark theme): the colour shown is the colour saved,
    // so the drawing looks the same on the phone. Unless the user already picked their own.
    const t = parseRgb(getComputedStyle(quill.root).color)
    if (t && !penColorTouched) penColor.value = rgbToHex([t[0], t[1], t[2]])
  }
  liveStroke = null
  redrawStrokes()
}

function strokeScale() {
  const host = scrollHost()
  return host.clientWidth / referenceWidth(strokesData, strokesWidth)
}

function pointerPoint(e) {
  const host = scrollHost()
  const rect = strokeCanvas.value.getBoundingClientRect()
  return toReferencePoint(e.clientX - rect.left, e.clientY - rect.top, { scale: strokeScale(), scrollTop: host.scrollTop })
}

function currentLive() {
  if (!liveStroke) return null
  return makeStroke({ points: liveStroke.points, color: penColor.value, width: penWidth.value, eraser: eraser.value })
}

function onPointerDown(e) {
  if (!drawMode.value || !quill || e.button > 0) return
  // The page width is fixed by the first stroke; later strokes are measured against it.
  strokesWidth = nextStrokesWidth(strokesData, strokesWidth)
  strokeCanvas.value.setPointerCapture(e.pointerId)
  liveStroke = { points: [pointerPoint(e)] }
  redrawStrokes()
}

let moveFrame = 0
function onPointerMove(e) {
  if (!liveStroke) return
  const p = pointerPoint(e)
  const last = liveStroke.points[liveStroke.points.length - 1]
  if (p[0] === last[0] && p[1] === last[1]) return
  liveStroke.points.push(p)
  if (!moveFrame) {
    moveFrame = requestAnimationFrame(() => {
      moveFrame = 0
      redrawStrokes()
    })
  }
}

function onPointerUp() {
  if (!liveStroke) return
  const stroke = currentLive()
  liveStroke = null
  strokesData = [...strokesData, stroke]
  strokeCount.value = strokesData.length
  refreshStrokes()
  emit('update:modelValue', serialize())
}

function undoStroke() {
  if (!strokesData.length) return
  strokesData = strokesData.slice(0, -1)
  strokeCount.value = strokesData.length
  refreshStrokes()
  emit('update:modelValue', serialize())
}

function clearStrokes() {
  if (!strokesData.length) return
  if (!window.confirm('Remove the whole drawing from this note?')) return
  strokesData = []
  strokeCount.value = 0
  refreshStrokes()
  emit('update:modelValue', serialize())
}

// The pointer is over the drawing layer, so the wheel would not scroll the page: pass it on.
function onWheel(e) {
  const host = scrollHost()
  if (host) host.scrollTop += e.deltaY
}

// ── Undo / Redo ───────────────────────────────────────────────────────────
// Quill's history module records typing, deleting, formatting and image/divider embeds, so one stack
// covers everything the user can do in the note body. Ctrl+Z / Ctrl+Y keep working through the same stack.
const canUndo = ref(false)
const canRedo = ref(false)
function syncHistory() {
  const h = quill?.history
  canUndo.value = !!h && h.stack.undo.length > 0
  canRedo.value = !!h && h.stack.redo.length > 0
}
function undo() { quill?.history.undo(); syncHistory() }
function redo() { quill?.history.redo(); syncHistory() }

// ── Load content into Quill ───────────────────────────────────────────────
function loadIntoQuill(raw) {
  const { delta, images, strokes, strokesWidth: savedWidth } = parseIncoming(raw)
  imagesMap = { ...images }
  strokesData = Array.isArray(strokes) ? strokes : []
  strokesWidth = savedWidth || 0
  strokeCount.value = strokesData.length
  // Reserve image counter above any existing numeric suffixes to avoid clash
  for (const k of Object.keys(imagesMap)) {
    const m = k.match(/_(\d+)$/)
    if (m) imgCounter = Math.max(imgCounter, parseInt(m[1], 10) + 1)
  }
  internalUpdate = true
  quill.setContents({ ops: delta.length ? delta : [{ insert: '\n' }] }, Quill.sources.SILENT)
  nextTick(() => {
    refreshImageDom()
    refreshStrokes()
    internalUpdate = false
  })
}

// ── Mount ─────────────────────────────────────────────────────────────────
onMounted(() => {
  quill = new Quill(`#ql-container-${uid}`, {
    modules: {
      toolbar: `#ql-toolbar-${uid}`,
      history: { delay: 500, maxStack: 200, userOnly: true },
    },
    theme: 'snow',
    placeholder: 'Start writing…',
  })

  loadIntoQuill(props.modelValue)
  const host = scrollHost()
  if (host) {
    host.addEventListener('scroll', redrawStrokes, { passive: true })
    if (typeof ResizeObserver !== 'undefined') {
      strokeObserver = new ResizeObserver(() => refreshStrokes())
      strokeObserver.observe(host)
    }
  }
  // Tell the page what the loaded note looks like when this editor writes it out, so it can tell later
  // whether anything really changed.
  emit('ready', serialize())

  // Keep the Undo / Redo buttons in step with Quill's history stack
  quill.on('editor-change', syncHistory)
  syncHistory()

  quill.on('text-change', () => {
    // Skip our own programmatic writes (setContents on load)
    if (internalUpdate) return
    refreshImageDom()
    emit('update:modelValue', serialize())
  })
})

onBeforeUnmount(() => {
  strokeObserver?.disconnect()
  scrollHost()?.removeEventListener('scroll', redrawStrokes)
  quill = null
})

// ── React to external modelValue changes (e.g. version restore) ───────────
watch(() => props.modelValue, (val) => {
  if (!quill) return
  // Only re-load if the incoming string is a genuinely different serialization
  // than what we currently hold — otherwise every emit triggers a reload.
  if (val === serialize()) return
  loadIntoQuill(val)
})
</script>

<style lang="scss" scoped>
.prinotes-quill-wrapper {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

// The Quill snow toolbar
.ql-toolbar-row {
  border: 1px solid var(--color-border) !important;
  border-radius: 6px 6px 0 0;
  background: var(--color-main-background) !important;
  flex-shrink: 0;
  display: flex !important;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px;
  padding: 6px 8px !important;

  // Quill's Snow theme uses a dark grey (#444) for icons and text, which is unreadable on a dark Nextcloud
  // theme. Everything follows the Nextcloud theme colours instead, and every control is the same height.
  :deep(.ql-formats) {
    display: inline-flex !important;
    align-items: center;
    gap: 2px;
    margin: 0 10px 0 0 !important;
  }
  :deep(button) {
    width: 32px !important;
    height: 32px !important;
    padding: 4px !important;
    float: none !important;
    display: inline-flex !important;
    align-items: center;
    justify-content: center;
  }
  :deep(.ql-stroke) { stroke: var(--color-main-text) !important; }
  :deep(.ql-fill), :deep(.ql-stroke.ql-fill) { fill: var(--color-main-text) !important; }
  :deep(button:hover .ql-stroke), :deep(button.ql-active .ql-stroke),
  :deep(.ql-picker-label:hover .ql-stroke) { stroke: var(--color-primary-element) !important; }
  :deep(button:hover .ql-fill), :deep(button.ql-active .ql-fill) { fill: var(--color-primary-element) !important; }

  // Text style (P / H1..H3) and font size: a labelled box, same height as the buttons.
  :deep(.ql-picker) { color: var(--color-main-text) !important; height: 32px !important; font-size: 14px !important; }
  :deep(.ql-picker.ql-header) { width: 74px !important; }
  :deep(.ql-picker.ql-prinotes-size) { width: 64px !important; }
  :deep(.ql-picker.ql-header .ql-picker-label),
  :deep(.ql-picker.ql-prinotes-size .ql-picker-label) {
    display: inline-flex !important;
    align-items: center;
    height: 32px !important;
    padding: 0 20px 0 10px !important;
    border: 1px solid var(--color-border) !important;
    border-radius: 6px;
    box-sizing: border-box;
  }
  :deep(.ql-picker.ql-header .ql-picker-label::before),
  :deep(.ql-picker.ql-prinotes-size .ql-picker-label::before) { line-height: 30px !important; }
  :deep(.ql-picker.ql-header .ql-picker-label::before),
  :deep(.ql-picker.ql-header .ql-picker-item::before) { content: attr(data-label) !important; }
  :deep(.ql-picker-label svg) { right: 4px !important; margin-top: -9px !important; }
  :deep(.ql-picker.ql-color-picker),
  :deep(.ql-picker.ql-icon-picker) { width: 32px !important; }
  :deep(.ql-picker.ql-color-picker .ql-picker-label) { padding: 4px !important; width: 32px !important; height: 32px !important; border: 0 !important; }
  :deep(.ql-picker-options) {
    background: var(--color-main-background) !important;
    border: 1px solid var(--color-border) !important;
    color: var(--color-main-text) !important;
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.35);
  }
  :deep(.ql-picker-item:hover), :deep(.ql-picker-item.ql-selected), :deep(.ql-picker-label:hover) {
    color: var(--color-primary-element) !important;
  }
}

.pn-undo[disabled],
.pn-redo[disabled] { opacity: 0.35; cursor: default; }
:deep(.pn-undo),
:deep(.pn-redo) { font-size: 1.1rem; line-height: 1; }

// Custom draw & divider buttons — Quill's built-in buttons all use ::before
// for icons; keep ours simple with unicode
:deep(.ql-prinotes-draw),
:deep(.ql-prinotes-divider) {
  font-size: 1rem;
  line-height: 1;
}

.ql-stage {
  position: relative;
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

// Transparent layer over the text for drawings made on the phone; never takes clicks.
.stroke-layer {
  position: absolute;
  pointer-events: none;
  z-index: 2;
}

.ql-target {
  flex: 1;
  min-height: 0;
  border: 1px solid var(--color-border) !important;
  border-top: none !important;
  border-radius: 0 0 6px 6px;
  background: var(--color-main-background) !important;
  overflow-y: auto;
}

:deep(.ql-container) {
  font-family: inherit;
  font-size: 1rem;
  border: none !important;
}

:deep(.ql-editor) {
  // Quill's default snow.css leaves .ql-editor with no explicit width and
  // its overflow-y:auto makes some browsers collapse it to intrinsic width
  // inside a flex parent — force full-width fill instead.
  width: 100%;
  box-sizing: border-box;
  min-height: 300px;
  color: var(--color-main-text);
  line-height: 1.5;
  padding: 20px 24px 80px;

  h1 { font-size: 1.8rem; font-weight: 700; }
  h2 { font-size: 1.4rem; font-weight: 700; }
  h3 { font-size: 1.15rem; font-weight: 700; }

  blockquote {
    border-left: 3px solid var(--color-primary-element);
    padding-left: 14px;
    color: var(--color-text-lighter);
    font-style: italic;
    margin: 8px 0;
  }

  pre.ql-syntax,
  .ql-code-block-container {
    background: var(--color-background-dark, #1e1e2e);
    color: #e4e4e4;
    border-radius: 6px;
    padding: 12px 14px;
    font-family: 'Fira Code', 'Consolas', monospace;
    font-size: 0.9rem;
  }

  // Checklist visual (Quill renders these as <li data-list="checked/unchecked">)
  li[data-list="checked"] > .ql-ui::before,
  li[data-list="unchecked"] > .ql-ui::before {
    cursor: pointer;
  }
}

:deep(.prinotes-image-embed) {
  display: block;
  margin: 12px 0;
  text-align: left;
  img {
    display: inline-block;
    max-width: 100%;
    border-radius: 4px;
  }
}

:deep(.prinotes-image-missing) {
  padding: 12px;
  border: 1px dashed var(--color-border);
  color: var(--color-text-lighter);
  text-align: center;
  font-size: 0.8rem;
  border-radius: 4px;
}

:deep(.prinotes-divider-embed) {
  border: none;
  border-top: 2px solid var(--color-border);
  margin: 16px 0;
}

// The Quill toolbar picker text (H1/H2/H3/P and font-size labels) can look
// tiny in dark theme — bump slightly for readability
:deep(.ql-prinotes-size .ql-picker-label::before),
:deep(.ql-prinotes-size .ql-picker-item::before) {
  content: attr(data-value) !important;
}
:deep(.ql-prinotes-size .ql-picker-label:not([data-value])::before) {
  content: '15' !important;
}
:deep(.ql-prinotes-size .ql-picker-label[data-value]::before) {
  content: attr(data-value) !important;
}

// Drawing overlay
.draw-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 6px 8px;
  border: 1px solid var(--color-border);
  border-top: none;
  background: var(--color-background-hover);
  flex-shrink: 0;

  button { padding: 2px 10px; min-height: 30px; }
  button.on { background: var(--color-primary-element); color: var(--color-primary-element-text); }
  button.done { margin-left: auto; font-weight: 600; }
  input[type='color'] { width: 34px; height: 30px; padding: 0; border: 1px solid var(--color-border); border-radius: 6px; cursor: pointer; }
  input[type='range'] { width: 110px; }
  .draw-size { min-width: 1.6em; text-align: right; font-size: 0.85rem; }
}

.stroke-layer.drawing {
  pointer-events: auto;
  touch-action: none;
  cursor: crosshair;
}

:deep(.ql-prinotes-draw.pn-active) {
  background: var(--color-primary-element-light, rgba(0, 130, 201, 0.2));
  border-radius: 4px;
}
</style>
