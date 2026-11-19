/**
 * Freehand drawings made in the Android app are saved as `strokes` in the note:
 *   { pts: [[x, y], ...], color: '0xAARRGGBB', width, eraser }
 * in the phone's own units. These helpers draw them on a canvas, scaled to the web editor.
 */

const PHONE_WIDTH = 360

/** Android '0xAARRGGBB' (or '#RRGGBB') to a CSS colour. Unreadable input gives black. */
export function colorToCss(hex) {
  if (typeof hex !== 'string') return 'rgba(0, 0, 0, 1)'
  let s = hex.trim()
  let a = 255
  let rgb
  if (/^0x[0-9a-f]{8}$/i.test(s)) {
    a = parseInt(s.slice(2, 4), 16)
    rgb = s.slice(4)
  } else if (/^#[0-9a-f]{6}$/i.test(s)) {
    rgb = s.slice(1)
  } else {
    return 'rgba(0, 0, 0, 1)'
  }
  const r = parseInt(rgb.slice(0, 2), 16)
  const g = parseInt(rgb.slice(2, 4), 16)
  const b = parseInt(rgb.slice(4, 6), 16)
  const alpha = a === 255 ? 1 : Math.round((a / 255) * 1000) / 1000
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

function validPoints(stroke) {
  if (!stroke || !Array.isArray(stroke.pts)) return []
  return stroke.pts.filter((p) => Array.isArray(p) && Number.isFinite(p[0]) && Number.isFinite(p[1]))
}

/**
 * The page width the drawing was made on. New drawings carry it (`strokesWidth`); older ones do not, so a
 * phone width is assumed, widened if the drawing reaches further right than that.
 */
export function referenceWidth(strokes, savedWidth) {
  if (Number.isFinite(savedWidth) && savedWidth > 0) return savedWidth
  let maxX = 0
  for (const s of strokes || []) for (const p of validPoints(s)) maxX = Math.max(maxX, p[0])
  return Math.max(PHONE_WIDTH, maxX > PHONE_WIDTH ? maxX + 16 : 0)
}

/** The lowest point of the drawing, in phone units. */
export function strokesBottom(strokes) {
  let max = 0
  for (const s of strokes || []) for (const p of validPoints(s)) max = Math.max(max, p[1])
  return max
}

/** Reads a CSS colour as the browser reports it ('rgb(..)', 'rgba(..)' or '#rrggbb') into [r, g, b, alpha]. */
export function parseRgb(css) {
  if (typeof css !== 'string') return null
  const m = css.match(/^rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)(?:[,\s/]+([\d.]+))?\s*\)$/i)
  if (m) return [Number(m[1]), Number(m[2]), Number(m[3]), m[4] === undefined ? 1 : Number(m[4])]
  const h = css.trim().match(/^#([0-9a-f]{6})$/i)
  if (h) return [parseInt(h[1].slice(0, 2), 16), parseInt(h[1].slice(2, 4), 16), parseInt(h[1].slice(4, 6), 16), 1]
  return null
}

function luminance([r, g, b]) {
  const f = (v) => {
    const c = v / 255
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
}

function contrast(a, b) {
  const x = luminance(a)
  const y = luminance(b)
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
}

/**
 * A drawing made with a white pen on the phone's dark page (or a black pen on a light one) would be
 * invisible on the web page when the themes differ. Ink with too little contrast against the page
 * background is shown in the page's text colour instead; every other colour is kept.
 */
export function readableInk(inkCss, background, foreground) {
  const ink = parseRgb(inkCss)
  if (!ink || !background || !foreground) return inkCss
  if (contrast(ink, background) >= 2) return inkCss
  return `rgba(${foreground[0]}, ${foreground[1]}, ${foreground[2]}, ${ink[3]})`
}

/** Draws every stroke in order. Erasers remove earlier ink. [scale] maps phone units to pixels. */
export function drawStrokes(ctx, strokes, { scale = 1, offsetY = 0, background = null, foreground = null } = {}) {
  for (const stroke of strokes || []) {
    const pts = validPoints(stroke)
    if (!pts.length) continue
    const x = (p) => p[0] * scale
    const y = (p) => p[1] * scale - offsetY
    const width = Math.max(0.5, (Number(stroke.width) || 4) * scale)
    const raw = colorToCss(stroke.color)
    const color = stroke.eraser ? raw : readableInk(raw, background, foreground)
    const op = stroke.eraser ? 'destination-out' : 'source-over'

    ctx.save()
    ctx.globalCompositeOperation = op
    if (pts.length < 2) {
      ctx.beginPath()
      ctx.fillStyle = color
      ctx.arc(x(pts[0]), y(pts[0]), width / 2, 0, Math.PI * 2)
      ctx.fill()
    } else {
      ctx.beginPath()
      ctx.strokeStyle = color
      ctx.lineWidth = width
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.moveTo(x(pts[0]), y(pts[0]))
      // Smooth through the points, the same way the phone draws it.
      for (let i = 1; i < pts.length - 1; i++) {
        const mx = (x(pts[i]) + x(pts[i + 1])) / 2
        const my = (y(pts[i]) + y(pts[i + 1])) / 2
        ctx.quadraticCurveTo(x(pts[i]), y(pts[i]), mx, my)
      }
      ctx.lineTo(x(pts[pts.length - 1]), y(pts[pts.length - 1]))
      ctx.stroke()
    }
    ctx.restore()
  }
}

/** A pointer position in the editor (pixels) as a point on the phone's page: zoom and scroll removed. */
export function toReferencePoint(px, py, { scale, scrollTop }) {
  const r = (v) => Math.round(v * 100) / 100
  return [r(px / scale), r((py + scrollTop) / scale)]
}

/** '#rrggbb' from the colour picker as the phone's '0xAARRGGBB'. */
export function hexToAndroid(hex) {
  const m = typeof hex === 'string' ? hex.trim().match(/^#([0-9a-f]{6})$/i) : null
  return '0xff' + (m ? m[1].toLowerCase() : '000000')
}

/** A stroke in the exact shape the phone saves. The phone's eraser is three times the pen width. */
export function makeStroke({ points, color, width, eraser }) {
  return {
    pts: points,
    color: hexToAndroid(color),
    width: eraser ? width * 3 : width,
    eraser: !!eraser,
  }
}

/** The page width to save with the strokes: the note's own if it has one, else what showing it would assume. */
export function nextStrokesWidth(strokes, savedWidth) {
  return referenceWidth(strokes, savedWidth)
}

/** [r, g, b] as '#rrggbb', for the colour picker. */
export function rgbToHex([r, g, b]) {
  return '#' + [r, g, b].map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('')
}
