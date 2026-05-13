import { ref, computed, watch, onUnmounted } from 'vue'

/**
 * Encapsulates all image-block state and logic.
 * Kept in a separate module so esbuild minifies it in its own scope,
 * avoiding the '$' identifier collision that occurs when too many
 * bindings share the same large <script setup> scope.
 */
export function useImageBlock(props, emit) {
  const imageCaption    = ref(props.block.caption      || '')
  const imgContainerEl  = ref(null)
  const imageWidthPx    = ref(props.block.displayWidth || null)
  const imageRotation   = ref(props.block.rotation     || 0)
  const isResizing      = ref(false)
  let resizeStartX      = 0
  let resizeStartWidth  = 0

  const imageAspect        = ref(0.6)
  const containerMeasuredW = ref(0)

  function onImageLoad(e) {
    const nw = e.target.naturalWidth
    const nh = e.target.naturalHeight
    if (nw && nh) imageAspect.value = nh / nw
    if (!imageWidthPx.value) {
      containerMeasuredW.value = imgContainerEl.value?.offsetWidth || 0
    }
  }

  // Returns { frameStyle, imgStyle } for the template.
  // One computed keeps the scope smaller and avoids duplicate minified names.
  const imageLayout = computed(() => {
    const rotation = imageRotation.value || 0
    const dispW    = imageWidthPx.value || containerMeasuredW.value || 400
    const dispH    = dispW * imageAspect.value
    const deg      = rotation * 180 / Math.PI

    // No rotation — normal block layout
    if (Math.abs(rotation) < 0.001) {
      return {
        frameStyle: imageWidthPx.value
          ? { position: 'relative', display: 'inline-block', width: dispW + 'px', maxWidth: '100%' }
          : { position: 'relative', display: 'block', width: '100%' },
        imgStyle: { display: 'block', width: '100%', maxWidth: '100%', height: 'auto' },
      }
    }

    // Axis-aligned bounding box of the rotated image
    const absCos   = Math.abs(Math.cos(rotation))
    const absSin   = Math.abs(Math.sin(rotation))
    const bbW      = dispW * absCos + dispH * absSin
    const bbH      = dispW * absSin + dispH * absCos
    const edgeMaxW = imgContainerEl.value?.parentElement?.offsetWidth || 9999

    let finalImgW = dispW
    let finalImgH = dispH
    let finalBbW  = Math.round(bbW)
    let finalBbH  = Math.round(bbH)

    // Scale down if the bounding box is wider than the editor column
    if (bbW > edgeMaxW) {
      const ratio = edgeMaxW / bbW
      finalImgW   = dispW * ratio
      finalImgH   = dispH * ratio
      finalBbW    = edgeMaxW
      finalBbH    = Math.round(bbH * ratio)
    }

    return {
      // Container sized to the full rotated footprint — text flows around it
      frameStyle: {
        position: 'relative',
        width: finalBbW + 'px',
        height: finalBbH + 'px',
        maxWidth: '100%',
      },
      // Image centered inside, then rotated
      imgStyle: {
        position: 'absolute',
        top: '50%',
        left: '50%',
        maxWidth: 'none',
        width:  Math.round(finalImgW) + 'px',
        height: Math.round(finalImgH) + 'px',
        transform: `translate(-50%,-50%) rotate(${deg}deg)`,
        transformOrigin: 'center center',
      },
    }
  })

  const RAD15 = Math.PI / 12   // 15° per button click

  function rotateImage(deltaRad) {
    imageRotation.value = (imageRotation.value || 0) + deltaRad
    emit('update', { ...props.block, rotation: imageRotation.value, caption: imageCaption.value })
  }

  watch(() => props.block.rotation, v => {
    if (!isResizing.value) imageRotation.value = v || 0
  })

  function onResizeMove(e) {
    const delta = e.clientX - resizeStartX
    const maxW  = imgContainerEl.value?.parentElement?.offsetWidth || 9999
    imageWidthPx.value = Math.max(80, Math.min(maxW, resizeStartWidth + delta))
  }

  function stopResize() {
    isResizing.value = false
    document.body.style.userSelect = ''
    document.removeEventListener('mousemove', onResizeMove)
    document.removeEventListener('mouseup',   stopResize)
    emit('update', {
      ...props.block,
      displayWidth: Math.round(imageWidthPx.value),
      rotation: imageRotation.value,
      caption: imageCaption.value,
    })
  }

  function startResize(e) {
    isResizing.value  = true
    resizeStartX      = e.clientX
    resizeStartWidth  = imageWidthPx.value || containerMeasuredW.value || 400
    document.body.style.userSelect = 'none'
    document.addEventListener('mousemove', onResizeMove)
    document.addEventListener('mouseup',   stopResize)
  }

  function resetImageWidth() {
    imageWidthPx.value = null
    emit('update', { ...props.block, displayWidth: null, rotation: imageRotation.value, caption: imageCaption.value })
  }

  watch(() => props.block.displayWidth, v => {
    if (!isResizing.value) imageWidthPx.value = v || null
  })

  onUnmounted(() => {
    document.removeEventListener('mousemove', onResizeMove)
    document.removeEventListener('mouseup',   stopResize)
    document.body.style.userSelect = ''
  })

  return {
    imageCaption,
    imgContainerEl,
    imageLayout,
    RAD15,
    onImageLoad,
    rotateImage,
    startResize,
    resetImageWidth,
  }
}
