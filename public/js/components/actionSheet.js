// actionSheet.js — iOS-style bottom action sheet
import { t } from "../i18n/index.js";

function esc(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

let activeSheet = null;

/**
 * Shows a bottom action sheet.
 * @param {{
 *   title?: string,
 *   message?: string,
 *   actions: Array<{ label: string, icon?: string, destructive?: boolean, onClick?: () => void }>,
 *   cancelLabel?: string,
 * }} options
 * @returns {() => void} close function
 */
export function showActionSheet({ title = "", message = "", actions = [], cancelLabel } = {}) {
  activeSheet?.();

  const overlay = document.createElement("div");
  overlay.className = "mori-action-sheet-overlay";

  const sheet = document.createElement("div");
  sheet.className = "mori-action-sheet";
  sheet.setAttribute("role", "menu");

  const group = document.createElement("div");
  group.className = "mori-action-sheet-group";

  if (title || message) {
    const head = document.createElement("div");
    head.className = "mori-action-sheet-head";
    head.innerHTML = `
      ${title ? `<div class="mori-action-sheet-title">${esc(title)}</div>` : ""}
      ${message ? `<div class="mori-action-sheet-message">${esc(message)}</div>` : ""}
    `;
    group.appendChild(head);
  }

  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    if (activeSheet === close) activeSheet = null;
    document.removeEventListener("keydown", onKey);
    overlay.classList.remove("visible");
    setTimeout(() => overlay.remove(), 220);
  };
  const onKey = (e) => {
    if (e.key === "Escape") close();
  };

  actions.forEach((action) => {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "mori-action-sheet-btn" + (action.destructive ? " destructive" : "");
    btn.setAttribute("role", "menuitem");
    btn.innerHTML = `${action.icon || ""}<span>${esc(action.label)}</span>`;
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      close();
      // Let the sheet start closing before opening follow-up dialogs
      setTimeout(() => action.onClick?.(), 60);
    });
    group.appendChild(btn);
  });

  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "mori-action-sheet-btn mori-action-sheet-cancel";
  cancel.textContent = cancelLabel || t("btn-cancel");
  cancel.addEventListener("click", (e) => {
    e.stopPropagation();
    close();
  });

  sheet.appendChild(group);
  sheet.appendChild(cancel);
  overlay.appendChild(sheet);
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) close();
  });
  document.addEventListener("keydown", onKey);
  document.body.appendChild(overlay);

  try {
    window.getSelection()?.removeAllRanges();
  } catch (_) {}
  requestAnimationFrame(() => overlay.classList.add("visible"));

  activeSheet = close;
  return close;
}
