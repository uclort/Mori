// imageLightbox.js — fullscreen image preview with swipe navigation
import { t } from "../i18n/index.js";

/**
 * Opens a fullscreen image viewer.
 * @param {{
 *   images: string[],
 *   startIndex?: number,
 *   loadImage?: (img: HTMLImageElement, src: string) => void,
 *   onDownload?: (index: number) => void,
 * }} options
 */
export function openImageLightbox({ images = [], startIndex = 0, loadImage, onDownload } = {}) {
  if (!images.length) return;
  let index = Math.min(Math.max(0, startIndex), images.length - 1);
  let zoomed = false;

  const overlay = document.createElement("div");
  overlay.className = "mori-lightbox";
  overlay.innerHTML = `
    <div class="mori-lightbox-top">
      <span class="mori-lightbox-counter"></span>
      <button type="button" class="mori-lightbox-close" aria-label="${t("btn-close")}">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
      </button>
    </div>
    <div class="mori-lightbox-stage"><img class="mori-lightbox-img" alt="" /></div>
    <button type="button" class="mori-lightbox-nav prev" aria-label="Previous">
      <svg viewBox="0 0 24 24" width="26" height="26" fill="currentColor"><path d="M15.41 7.41L14 6l-6 6 6 6 1.41-1.41L10.83 12z"/></svg>
    </button>
    <button type="button" class="mori-lightbox-nav next" aria-label="Next">
      <svg viewBox="0 0 24 24" width="26" height="26" fill="currentColor"><path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"/></svg>
    </button>
    ${
      onDownload
        ? `<div class="mori-lightbox-bottom">
             <button type="button" class="mori-lightbox-download">
               <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>
               <span></span>
             </button>
           </div>`
        : ""
    }
  `;

  const imgEl = overlay.querySelector(".mori-lightbox-img");
  const counter = overlay.querySelector(".mori-lightbox-counter");
  const prevBtn = overlay.querySelector(".prev");
  const nextBtn = overlay.querySelector(".next");
  const dlBtn = overlay.querySelector(".mori-lightbox-download");

  const setZoom = (z) => {
    zoomed = z;
    imgEl.classList.toggle("zoomed", z);
  };

  const render = () => {
    setZoom(false);
    imgEl.removeAttribute("data-retry");
    imgEl.removeAttribute("data-local-retried");
    imgEl.style.display = "";
    if (loadImage) loadImage(imgEl, images[index]);
    else imgEl.src = images[index];
    counter.textContent = images.length > 1 ? `${index + 1} / ${images.length}` : "";
    const multi = images.length > 1;
    prevBtn.style.display = multi ? "" : "none";
    nextBtn.style.display = multi ? "" : "none";
    if (dlBtn) {
      dlBtn.querySelector("span").textContent = t("btn-download-this-photo", { index: index + 1 });
    }
  };

  const go = (delta) => {
    if (images.length < 2) return;
    index = (index + delta + images.length) % images.length;
    render();
  };

  const close = () => {
    document.removeEventListener("keydown", onKey);
    overlay.classList.remove("visible");
    setTimeout(() => overlay.remove(), 200);
  };
  const onKey = (e) => {
    if (e.key === "Escape") close();
    else if (e.key === "ArrowLeft") go(-1);
    else if (e.key === "ArrowRight") go(1);
  };

  prevBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    go(-1);
  });
  nextBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    go(1);
  });
  overlay.querySelector(".mori-lightbox-close").addEventListener("click", (e) => {
    e.stopPropagation();
    close();
  });
  dlBtn?.addEventListener("click", (e) => {
    e.stopPropagation();
    onDownload(index);
  });

  // Tap backdrop to close, double-tap image to zoom
  let lastTap = 0;
  overlay.querySelector(".mori-lightbox-stage").addEventListener("click", (e) => {
    if (e.target !== imgEl) {
      close();
      return;
    }
    const now = Date.now();
    if (now - lastTap < 300) setZoom(!zoomed);
    lastTap = now;
  });

  // Horizontal swipe to navigate
  let sx = 0;
  let sy = 0;
  overlay.addEventListener(
    "touchstart",
    (e) => {
      if (e.touches.length !== 1) return;
      sx = e.touches[0].clientX;
      sy = e.touches[0].clientY;
    },
    { passive: true },
  );
  overlay.addEventListener(
    "touchend",
    (e) => {
      if (zoomed) return;
      const touch = e.changedTouches[0];
      if (!touch) return;
      const dx = touch.clientX - sx;
      const dy = touch.clientY - sy;
      if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) go(dx < 0 ? 1 : -1);
      else if (dy > 90 && Math.abs(dy) > Math.abs(dx) * 1.5) close();
    },
    { passive: true },
  );

  document.addEventListener("keydown", onKey);
  document.body.appendChild(overlay);
  render();
  requestAnimationFrame(() => overlay.classList.add("visible"));
  return close;
}
