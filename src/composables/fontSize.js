/**
 * The Android app saves a font size as a bare number ("28"); the web used to expect "28px". These helpers
 * let the web read and write the phone's form, and still accept the old "28px" form from earlier web saves.
 */

/** The sizes both apps offer, as the phone stores them. */
export const FONT_SIZES = ['12', '15', '18', '22', '28']

/** "28", 28 or "28px" as a CSS size ("28px"). Anything unreadable is returned as it came. */
export function toPxSize(value) {
  const n = parseFloat(String(value))
  return Number.isFinite(n) ? `${n}px` : value
}

/** A CSS size ("28px") as the phone stores it ("28"). Empty stays empty. */
export function fromPxSize(css) {
  return typeof css === 'string' ? css.replace(/px$/i, '') : css
}
