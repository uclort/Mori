// album.js — save downloaded media into the system photo library (iOS Photos / Android MediaStore)
import { Filesystem } from "../utils/index.js";

export const SAVE_TARGET_KEY = "mori_save_target";
const SAVE_TARGETS = ["files", "album", "both"];
const ANDROID_ALBUM_NAME = "Mori";

// Formats the system photo library can ingest. Everything else (PDF, audio,
// mkv/webm video, ...) always stays in the Files folder regardless of setting.
const ALBUM_IMAGE_EXT = /\.(jpe?g|png|webp|gif|heic|heif)$/i;
const ALBUM_VIDEO_EXT = /\.(mp4|mov|m4v)$/i;

/**
 * Where downloads should go: "files" (default) | "album" | "both"
 */
export function getSaveTarget() {
  const v = localStorage.getItem(SAVE_TARGET_KEY);
  return SAVE_TARGETS.includes(v) ? v : "files";
}

/**
 * @returns {"image"|"video"|null} album media kind, or null when the file can't go into the photo library
 */
export function albumMediaKind(fileName) {
  const name = String(fileName || "").split("?")[0];
  if (ALBUM_IMAGE_EXT.test(name)) return "image";
  if (ALBUM_VIDEO_EXT.test(name)) return "video";
  return null;
}

export function isAlbumSupported() {
  const platform = window.Capacitor?.getPlatform?.();
  return (
    (platform === "ios" || platform === "android") &&
    Boolean(window.Capacitor?.Plugins?.Media)
  );
}

let androidAlbumIdPromise = null;
async function getAndroidAlbumId(Media) {
  if (!androidAlbumIdPromise) {
    androidAlbumIdPromise = (async () => {
      const find = async () => {
        const res = await Media.getAlbums();
        return (res?.albums || []).find((a) => a.name === ANDROID_ALBUM_NAME);
      };
      let album = await find();
      if (!album) {
        await Media.createAlbum({ name: ANDROID_ALBUM_NAME });
        album = await find();
      }
      return album?.identifier || null;
    })().catch((e) => {
      androidAlbumIdPromise = null;
      throw e;
    });
  }
  return androidAlbumIdPromise;
}

/**
 * Resolves a properly percent-encoded file:// URL the native layer can parse.
 * (Decoded URIs with spaces / CJK characters make iOS URL(string:) return nil.)
 */
async function resolveNativeFileUrl({ path, directory, uri }) {
  let raw = "";
  if (Filesystem && path && directory && directory !== "DESKTOP") {
    try {
      const res = await Filesystem.getUri({ path, directory });
      if (res?.uri) raw = res.uri;
    } catch (_) {}
  }
  if (!raw) raw = String(uri || path || "");
  if (raw.includes("_capacitor_file_")) {
    raw = "file://" + raw.substring(raw.indexOf("_capacitor_file_") + 16);
  }
  if (!raw.startsWith("file://")) {
    raw = "file://" + (raw.startsWith("/") ? raw : "/" + raw);
  }
  try {
    // Normalize: decode first so already-encoded parts are not double-encoded
    return encodeURI(decodeURI(raw));
  } catch (_) {
    return encodeURI(raw);
  }
}

/**
 * Saves a local file into the photo library.
 * @param {{path?: string, directory?: string, uri?: string, name?: string}} file
 * @returns {Promise<{ok: boolean, reason?: "unsupported"|"denied"|"failed", error?: any}>}
 */
export async function saveFileToAlbum(file) {
  const Media = window.Capacitor?.Plugins?.Media;
  const kind = albumMediaKind(file?.name || file?.path || file?.uri);
  if (!kind || !Media || !isAlbumSupported()) {
    return { ok: false, reason: "unsupported" };
  }
  try {
    const fileUrl = await resolveNativeFileUrl(file);
    const opts = { path: fileUrl };
    if (window.Capacitor.getPlatform() === "android") {
      const albumId = await getAndroidAlbumId(Media);
      if (!albumId) return { ok: false, reason: "failed" };
      opts.albumIdentifier = albumId;
    }
    if (kind === "video") await Media.saveVideo(opts);
    else await Media.savePhoto(opts);
    return { ok: true };
  } catch (error) {
    console.warn("Save to album failed:", error);
    const denied =
      error?.code === "accessDenied" || /not allowed|denied/i.test(error?.message || "");
    return { ok: false, reason: denied ? "denied" : "failed", error };
  }
}
