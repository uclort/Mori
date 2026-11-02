// appearance.js — theme, colors, typography, and visual presets
import { translations } from "../../i18n/index.js";
import { showToast } from "../../utils/index.js";
import { currentLang } from "../core.js";
import { syncSettingToNative } from "./nativeSync.js";

const accentColors = {
  black: { light: "#1a1917", dark: "#fffbf2" },
};

const THEME_MODES = ["system", "light", "dark"];
const darkQuery =
  typeof window !== "undefined" && window.matchMedia
    ? window.matchMedia("(prefers-color-scheme: dark)")
    : null;

/**
 * Theme preference: "system" (follow device) | "light" | "dark"
 */
export function getThemeMode() {
  const mode = localStorage.getItem("mori_theme_mode");
  if (THEME_MODES.includes(mode)) return mode;
  // Migrate users who picked a theme with the old on/off switch
  const legacy = localStorage.getItem("mori_theme");
  return legacy === "dark" || legacy === "light" ? legacy : "system";
}

function resolveTheme(mode) {
  if (mode === "system") return darkQuery?.matches ? "dark" : "light";
  return mode;
}

/**
 * Applies the effective theme for the current mode. "mori_theme" keeps holding the
 * resolved light/dark value because the share page and native side read it.
 */
export function applyThemeMode() {
  const theme = resolveTheme(getThemeMode());
  const changed = document.documentElement.getAttribute("data-theme") !== theme;
  document.documentElement.setAttribute("data-theme", theme);
  if (localStorage.getItem("mori_theme") !== theme) {
    localStorage.setItem("mori_theme", theme);
    syncSettingToNative("mori_theme", theme);
  }
  applyColorAccent();
  if (changed) {
    window.dispatchEvent(new CustomEvent("mori_theme_changed", { detail: { theme } }));
  }
}

export function applyColorAccent() {
  const theme = localStorage.getItem("mori_theme") || "light";
  const color = accentColors.black[theme] || "#1a1917";
  document.documentElement.style.setProperty("--primary", color);
}

export function applyFont() {
  if (!document.body) return;
  const font = localStorage.getItem("mori_font") || "display";
  document.body.className = (document.body.className || "").replace(
    /\bfont-\S+/g,
    "",
  );
  document.body.classList.add(`font-${font}`);
}

export function applyAnimSpeed() {
  if (!document.body) return;
  const speed = localStorage.getItem("mori_anim_speed") || "normal";
  document.body.classList.remove(
    "anim-off",
    "anim-slow",
    "anim-normal",
    "anim-fast",
  );
  document.body.classList.add(`anim-${speed}`);
}

export function applyTextSize() {
  const size = localStorage.getItem("mori_text_size") || "medium";
  const fontSizeMap = { small: "14px", medium: "16px", large: "18px" };
  document.documentElement.style.fontSize = fontSizeMap[size] || "16px";
  document.body.classList.remove("text-small", "text-medium", "text-large");
  document.body.classList.add(`text-${size}`);
}

export function applyGlassmorphism() {
  if (!document.body) return;
  const mode = localStorage.getItem("mori_glassmorphism") || "subtle";
  document.body.classList.remove("glass-off", "glass-subtle", "glass-deep");
  document.body.classList.add(`glass-${mode}`);
}

export function applyUiCorner() {
  if (!document.body) return;
  const corner = localStorage.getItem("mori_ui_corner") || "modern";
  document.body.classList.remove(
    "corner-sharp",
    "corner-modern",
    "corner-round",
  );
  document.body.classList.add(`corner-${corner}`);
}

export function applyGalleryVisibility() {
  const isEnabled = localStorage.getItem("mori_show_gallery") !== "false";
  const galleryNavItem = document.querySelector('.nav-item[data-page="gallery"]');
  if (galleryNavItem) {
    galleryNavItem.style.display = isEnabled ? "" : "none";
  }
}

/**
 * Initializes theme, typography, presets, and toggle listeners
 */
export function initAppearance() {
  // 1. Theme initialization (System / Light / Dark)
  if (!THEME_MODES.includes(localStorage.getItem("mori_theme_mode"))) {
    localStorage.setItem("mori_theme_mode", getThemeMode());
  }
  applyThemeMode();
  const onSystemThemeChange = () => {
    if (getThemeMode() === "system") applyThemeMode();
  };
  if (darkQuery?.addEventListener) darkQuery.addEventListener("change", onSystemThemeChange);
  else darkQuery?.addListener?.(onSystemThemeChange);
  // Some WebViews only re-evaluate the media query after returning to foreground
  window.addEventListener("mori_app_resumed", onSystemThemeChange);
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) onSystemThemeChange();
  });

  // 2. Compact mode initialization
  const compactModeToggle = document.getElementById("compactModeToggle");
  if (compactModeToggle) {
    compactModeToggle.checked =
      localStorage.getItem("mori_compact_mode") === "true";
    if (compactModeToggle.checked) document.body.classList.add("compact-mode");
    compactModeToggle.addEventListener("change", (e) => {
      localStorage.setItem("mori_compact_mode", e.target.checked);
      if (e.target.checked) {
        document.body.classList.add("compact-mode");
      } else {
        document.body.classList.remove("compact-mode");
      }
      const lang = translations[currentLang] || translations.en;
      showToast(
        e.target.checked
          ? lang["toast-compact-on"] || "Compact mode enabled"
          : lang["toast-compact-off"] || "Compact mode disabled",
      );
    });
  }

  // 3. Show Gallery Tab initialization
  const showGalleryToggle = document.getElementById("showGalleryToggle");
  if (showGalleryToggle) {
    showGalleryToggle.checked =
      localStorage.getItem("mori_show_gallery") !== "false";
    applyGalleryVisibility();
    showGalleryToggle.addEventListener("change", (e) => {
      const isEnabled = e.target.checked;
      localStorage.setItem("mori_show_gallery", isEnabled);
      applyGalleryVisibility();
      window.dispatchEvent(
        new CustomEvent("mori_gallery_visibility_changed", {
          detail: { isEnabled },
        }),
      );

      // If user is currently on gallery page and disables it, redirect to home
      const activeNav = document.querySelector(".nav-item.active");
      if (!isEnabled && activeNav?.getAttribute("data-page") === "gallery") {
        document.querySelector('.nav-item[data-page="home"]')?.click();
      }

      const lang = translations[currentLang] || translations.en;
      showToast(
        isEnabled
          ? lang["toast-gallery-tab-on"] || "Gallery tab enabled"
          : lang["toast-gallery-tab-off"] || "Gallery tab hidden",
      );
    });
  }

  // 4. Apply active visual presets
  applyColorAccent();
  applyFont();
  applyAnimSpeed();
  applyTextSize();
  applyGlassmorphism();
  applyUiCorner();
  applyGalleryVisibility();
}
