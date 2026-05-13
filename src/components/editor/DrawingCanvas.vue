<template>
  <div class="drawing-overlay" @click.self="$emit('close')">
    <div class="drawing-modal">

      <!-- ── Header toolbar ─────────────────────────────────────────────── -->
      <div class="drawing-header">
        <h3>Drawing Canvas</h3>

        <div class="drawing-tools">
          <!-- Colors -->
          <div class="color-swatches">
            <button
              v-for="c in penColors"
              :key="c"
              class="pen-color"
              :class="{ active: penColor === c && !isEraser }"
              :style="{ background: c, borderColor: c === '#1e1e2e' ? '#555' : 'transparent' }"
              @click="penColor = c; isEraser = false"
              :title="c"
            />
          </div>

          <div class="tool-sep" />

          <!-- Pen button + size popup -->
          <div class="tool-btn-wrap" ref="penBtnRef">
            <button
              class="btn btn-icon tool-btn"
              :class="{ active: !isEraser }"
              @click="togglePopup('pen')"
              title="Pen"
            >
              <Pen :size="18" />
            </button>
            <!-- Live size dot -->
            <div
              v-if="!isEraser"
              class="size-dot"
              :style="{ width: dotSize + 'px', height: dotSize + 'px', background: penColor }"
            />
            <!-- Pen size popup -->
            <div v-if="activePopup === 'pen'" class="size-popup" @click.stop>
              <div class="popup-preview" :style="{ background: penColor }">
                <div
                  class="popup-dot"
                  :style="{ width: penSize + 'px', height: penSize + 'px', background: penColor }"
                />
              </div>
              <input
                type="range" min="1" max="30" step="1"
                v-model.number="penSize"
                class="size-slider"
                orient="vertical"
              />
            </div>
          </div>

          <!-- Eraser button + size popup -->
          <div class="tool-btn-wrap" ref="eraserBtnRef">
            <button
              class="btn btn-icon tool-btn"
              :class="{ active: isEraser }"
              @click="togglePopup('eraser')"
              title="Eraser"
            >
              <!-- Custom eraser shape (rectangle with color band) -->
              <svg width="20" height="13" viewBox="0 0 20 13" class="eraser-icon">
                <rect x="0.75" y="0.75" width="18.5" height="11.5" rx="2" fill="rgba(128,128,128,0.15)" stroke="currentColor" stroke-width="1.5"/>
                <rect x="13.5" y="0.75" width="5.75" height="11.5" rx="0" fill="currentColor" opacity="0.45"/>
              </svg>
            </button>
            <div
              v-if="isEraser"
              class="size-dot eraser-dot"
              :style="{ width: dotSize + 'px', height: dotSize + 'px' }"
            />
            <!-- Eraser size popup -->
            <div v-if="activePopup === 'eraser'" class="size-popup" @click.stop>
              <div class="popup-preview eraser-preview">
                <div
                  class="popup-dot eraser-dot-preview"
                  :style="{ width: eraserSize + 'px', height: eraserSize + 'px' }"
                />
              </div>
              <input
                type="range" min="4" max="60" step="2"
                v-model.number="eraserSize"
                class="size-slider"
                orient="vertical"
              />
            </div>
          </div>

          <div class="tool-sep" />

          <button class="btn btn-icon" @click="undo"  title="Undo"><Undo  :size="18" /></button>
          <button class="btn btn-icon" @click="redo"  title="Redo"><Redo  :size="18" /></button>
          <button class="btn btn-icon" @click="clearCanvas" title="Clear all"><Delete :size="18" /></button>

          <div class="tool-sep" />

          <!-- Background -->
          <select v-model="bgStyle" class="bg-select" @change="redrawAll">
            <option value="dark">Dark</option>
            <option value="grid">Grid</option>
            <option value="lines">Lines</option>
            <option value="dots">Dots</option>
            <option value="white">White</option>
          </select>
        </div>

        <div class="drawing-header-right">
          <button class="btn btn-primary" @click="saveDrawing">Save</button>
          <button class="btn" @click="$emit('close')">Cancel</button>
        </div>
      </div>

      <!-- ── Canvas ──────────────────────────────────────────────────────── -->
      <div ref="wrapperRef" class="canvas-wrapper" @click="closePopup">
        <canvas
          ref="canvasRef"
          :width="canvasWidth"
          :height="canvasHeight"
          @pointerdown="onPointerDown"
          @pointermove="onPointerMove"
          @pointerup="onPointerUp"
          @pointerleave="onPointerUp"
          class="drawing-canvas"
        />
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import Pen    from 'vue-material-design-icons/Pen.vue'
import Undo   from 'vue-material-design-icons/Undo.vue'
import Redo   from 'vue-material-design-icons/Redo.vue'
import Delete from 'vue-material-design-icons/Delete.vue'
import { getStroke } from 'perfect-freehand'

const props = defineProps({
  initialData: { type: Object, default: null },
})
const emit = defineEmits(['save', 'close'])

// ── Canvas refs & sizing ──────────────────────────────────────────────────────
const canvasRef   = ref(null)
const wrapperRef  = ref(null)
const canvasWidth  = ref(800)
const canvasHeight = ref(500)

// ── Tool state ────────────────────────────────────────────────────────────────
const penColor   = ref('#ffffff')
const penSize    = ref(4)
const eraserSize = ref(16)
const isEraser   = ref(false)
const bgStyle    = ref('dark')
const activePopup = ref(null)   // 'pen' | 'eraser' | null

const penColors = [
  '#ffffff', '#f8fafc', '#fbbf24', '#f87171', '#fb923c',
  '#4ade80', '#60a5fa', '#c084fc', '#f472b6', '#94a3b8', '#1e1e2e',
]

const bgColor = { dark: '#1e1e2e', grid: '#1e1e2e', lines: '#1e1e2e', dots: '#1e1e2e', white: '#ffffff' }

// Dot preview size (capped so it doesn't overwhelm the toolbar)
const dotSize = computed(() => {
  const s = isEraser.value ? eraserSize.value : penSize.value
  return Math.min(s, 14)
})

// ── Stroke history ────────────────────────────────────────────────────────────
const strokes      = ref([])
const undoStack    = ref([])
const currentStroke = ref(null)

let ctx = null
let isDrawing = false
let resizeObserver = null

// ── Lifecycle ─────────────────────────────────────────────────────────────────
onMounted(() => {
  ctx = canvasRef.value.getContext('2d')

  resizeObserver = new ResizeObserver(() => {
    const w = wrapperRef.value?.clientWidth  || 800
    const h = wrapperRef.value?.clientHeight || 500
    canvasWidth.value  = w
    canvasHeight.value = h
    setTimeout(redrawAll, 0)
  })
  resizeObserver.observe(wrapperRef.value)

  if (props.initialData?.strokes) strokes.value = props.initialData.strokes
})

onBeforeUnmount(() => resizeObserver?.disconnect())

// ── Popup toggle ──────────────────────────────────────────────────────────────
function togglePopup(tool) {
  if (tool === 'eraser') isEraser.value = true
  else                   isEraser.value = false
  activePopup.value = activePopup.value === tool ? null : tool
}

function closePopup() { activePopup.value = null }

// ── Pointer events ────────────────────────────────────────────────────────────
function onPointerDown(event) {
  closePopup()
  isDrawing = true
  canvasRef.value.setPointerCapture(event.pointerId)
  const { x, y } = getPos(event)
  currentStroke.value = {
    points:   [[x, y, event.pressure]],
    color:    isEraser.value ? bgColor[bgStyle.value] : penColor.value,
    size:     isEraser.value ? eraserSize.value : parseInt(penSize.value),
    isEraser: isEraser.value,
  }
}

function onPointerMove(event) {
  if (!isDrawing) return
  const { x, y } = getPos(event)
  currentStroke.value.points.push([x, y, event.pressure])
  renderFrame()
}

function onPointerUp() {
  if (!isDrawing) return
  isDrawing = false
  if (currentStroke.value?.points.length > 1) {
    strokes.value.push(currentStroke.value)
    undoStack.value = []
  }
  currentStroke.value = null
  redrawAll()
}

function getPos(event) {
  const rect = canvasRef.value.getBoundingClientRect()
  return { x: event.clientX - rect.left, y: event.clientY - rect.top }
}

// ── Rendering ─────────────────────────────────────────────────────────────────
function renderFrame() {
  redrawAll()
  if (currentStroke.value) drawStroke(ctx, currentStroke.value)
}

function redrawAll() {
  if (!ctx) return
  const w = canvasWidth.value
  const h = canvasHeight.value

  ctx.fillStyle = bgColor[bgStyle.value]
  ctx.fillRect(0, 0, w, h)

  if (bgStyle.value === 'grid') {
    ctx.strokeStyle = 'rgba(255,255,255,0.10)'
    ctx.lineWidth = 1
    for (let x = 0; x <= w; x += 24) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke() }
    for (let y = 0; y <= h; y += 24) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke() }
  } else if (bgStyle.value === 'lines') {
    ctx.strokeStyle = 'rgba(255,255,255,0.10)'
    ctx.lineWidth = 1
    for (let y = 28; y <= h; y += 28) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke() }
  } else if (bgStyle.value === 'dots') {
    ctx.fillStyle = 'rgba(255,255,255,0.22)'
    for (let x = 20; x < w; x += 20) {
      for (let y = 20; y < h; y += 20) {
        ctx.beginPath(); ctx.arc(x, y, 1.2, 0, Math.PI * 2); ctx.fill()
      }
    }
  }

  for (const stroke of strokes.value) drawStroke(ctx, stroke)
}

function drawStroke(ctx, stroke) {
  const points = getStroke(stroke.points, {
    size: stroke.size, thinning: 0.5, smoothing: 0.5, streamline: 0.5,
  })
  if (!points.length) return
  ctx.fillStyle = stroke.color
  ctx.beginPath()
  const [first, ...rest] = points
  ctx.moveTo(first[0], first[1])
  for (const [x, y] of rest) ctx.lineTo(x, y)
  ctx.closePath()
  ctx.fill()
}

// ── Undo / Redo / Clear ───────────────────────────────────────────────────────
function undo()  { if (strokes.value.length) { undoStack.value.push(strokes.value.pop()); redrawAll() } }
function redo()  { if (undoStack.value.length) { strokes.value.push(undoStack.value.pop()); redrawAll() } }
function clearCanvas() { undoStack.value.push(...strokes.value); strokes.value = []; redrawAll() }

// ── Save ──────────────────────────────────────────────────────────────────────
function saveDrawing() {
  const dataUrl = canvasRef.value.toDataURL('image/png')
  emit('save', { dataUrl, strokes: strokes.value, width: canvasWidth.value, height: canvasHeight.value })
}
</script>

<style lang="scss" scoped>
.drawing-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.72);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.drawing-modal {
  background: var(--color-main-background);
  border-radius: 12px;
  overflow: hidden;
  max-width: 95vw;
  max-height: 95vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 24px 64px rgba(0,0,0,0.35);
  width: 900px;
}

// ── Header ────────────────────────────────────────────────────────────────────
.drawing-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 14px;
  border-bottom: 1px solid var(--color-border);
  flex-wrap: wrap;
  background: var(--color-background-dark);

  h3 { margin: 0; font-size: 0.95rem; font-weight: 600; white-space: nowrap; }
}

.drawing-tools {
  display: flex;
  align-items: center;
  gap: 6px;
  flex: 1;
  flex-wrap: wrap;
}

.color-swatches { display: flex; gap: 4px; }

.pen-color {
  width: 20px;
  height: 20px;
  border-radius: 50%;
  border: 2px solid transparent;
  cursor: pointer;
  padding: 0;
  transition: transform 0.1s;
  &:hover { transform: scale(1.2); }
  &.active { border-color: var(--color-primary-element) !important; }
}

.tool-sep {
  width: 1px;
  height: 22px;
  background: var(--color-border);
  margin: 0 2px;
}

// ── Tool button + popup ───────────────────────────────────────────────────────
.tool-btn-wrap {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
}

.tool-btn {
  position: relative;
}

button.active {
  background: var(--color-primary-light, #dbedff);
  color: var(--color-primary-element, #0082c9);
}

.size-dot {
  border-radius: 50%;
  background: var(--color-text-lighter);
  flex-shrink: 0;
  transition: width 0.1s, height 0.1s;
  min-width: 3px;
  min-height: 3px;
  &.eraser-dot { background: var(--color-border); border: 1px solid var(--color-text-lighter); }
}

.size-popup {
  position: absolute;
  top: calc(100% + 8px);
  left: 50%;
  transform: translateX(-50%);
  background: var(--color-main-background);
  border: 1px solid var(--color-border);
  border-radius: 10px;
  padding: 10px 8px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  z-index: 500;
  box-shadow: 0 6px 20px rgba(0,0,0,0.2);
  width: 52px;
}

.popup-preview {
  width: 32px;
  height: 32px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--color-background-dark);
  &.eraser-preview { background: #888; }
}

.popup-dot {
  border-radius: 50%;
  background: #fff;
  transition: width 0.1s, height 0.1s;
  &.eraser-dot-preview { background: #1e1e2e; border: 1px solid rgba(255,255,255,0.4); }
}

.size-slider {
  writing-mode: vertical-lr;
  direction: rtl;
  width: 24px;
  height: 100px;
  cursor: pointer;
  accent-color: var(--color-primary-element);
}

.eraser-icon { display: block; }

// ── Background select ─────────────────────────────────────────────────────────
.bg-select {
  padding: 3px 6px;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 0.80rem;
  background: var(--color-main-background);
  color: var(--color-main-text);
  cursor: pointer;
}

.drawing-header-right {
  display: flex;
  gap: 8px;
  margin-left: auto;
}

// ── Canvas ────────────────────────────────────────────────────────────────────
.canvas-wrapper {
  overflow: auto;
  flex: 1;
  background: #1e1e2e;
}

.drawing-canvas {
  display: block;
  cursor: crosshair;
  touch-action: none;
}
</style>
