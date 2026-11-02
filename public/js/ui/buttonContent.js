// buttonContent.js — swap download button labels without destroying the photo thumbnail

/**
 * Inner HTML of a download button, excluding its preview thumbnail.
 */
export function getButtonContent(btn) {
  if (!btn) return "";
  const thumb = btn.querySelector(":scope > .dl-thumb");
  if (!thumb) return btn.innerHTML;
  const clone = btn.cloneNode(true);
  clone.querySelector(":scope > .dl-thumb")?.remove();
  return clone.innerHTML;
}

/**
 * Replaces a download button's content while keeping its thumbnail node (and listeners) intact.
 */
export function setButtonContent(btn, html) {
  if (!btn) return;
  const thumb = btn.querySelector(":scope > .dl-thumb");
  btn.innerHTML = html;
  if (thumb) btn.prepend(thumb);
}
