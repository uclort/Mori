// postProcess.js — post-download feedback, media scanning, notifications, and button reset
import {
  Filesystem,
  triggerHaptic,
  playCompletionSound,
  autoClearInputBox,
} from "../utils/index.js";
import { translations, t } from "../i18n/index.js";
import { currentLang } from "../modules/core.js";
import { showToast } from "../utils/toast.js";
import { setButtonContent } from "../ui/buttonContent.js";
import {
  getSaveTarget,
  albumMediaKind,
  isAlbumSupported,
  saveFileToAlbum,
} from "./album.js";

let lastAlbumToastAt = 0;
function albumToast(message) {
  // Avoid flooding the screen during multi-photo / playlist downloads
  const now = Date.now();
  if (now - lastAlbumToastAt < 2500) return;
  lastAlbumToastAt = now;
  showToast(message);
}

/**
 * Copies the freshly downloaded file into the photo library according to the
 * "Save Location" setting. Returns true when the local copy was removed
 * (album-only mode), so callers stop referencing it.
 */
async function applySaveTarget({ savedFile, successfulDir, savedUri, fileName }) {
  const target = getSaveTarget();
  if (target === "files" || !albumMediaKind(fileName) || !isAlbumSupported()) {
    return false;
  }
  const res = await saveFileToAlbum({
    path: savedFile.path,
    directory: successfulDir,
    uri: savedUri,
    name: fileName,
  });
  if (!res.ok) {
    albumToast(
      res.reason === "denied" ? t("toast-album-denied") : t("toast-album-failed"),
    );
    return false;
  }
  if (target === "album" && Filesystem && successfulDir !== "DESKTOP") {
    try {
      await Filesystem.deleteFile({ path: savedFile.path, directory: successfulDir });
      return true;
    } catch (e) {
      console.warn("Failed to remove local copy after album save:", e);
    }
  }
  return false;
}

/**
 * Handles all post-download actions: sound, haptics, URI resolution, MediaScanner, notifications, and UI reset
 */
export async function handlePostDownload({
  savedFile,
  successfulDir,
  sourceUrl,
  url,
  effectiveTitle,
  fileName,
  targetFolder,
  btn,
  originalContent,
  progressContainer,
}) {
  triggerHaptic("success");
  if (!window._moriPlaylistDownloading) {
    playCompletionSound();
    autoClearInputBox();
  }

  let savedUri = savedFile.uri || savedFile.path;
  if (
    !savedUri.startsWith("file://") &&
    !savedUri.startsWith("_capacitor_file_") &&
    window.Capacitor &&
    Filesystem
  ) {
    try {
      const uriObj = await Filesystem.getUri({
        path: savedFile.path,
        directory: successfulDir,
      });
      if (uriObj?.uri) savedUri = uriObj.uri;
    } catch (_) {}
  }

  try {
    if (savedUri.startsWith("file://")) {
      savedUri = decodeURI(savedUri);
    }
  } catch (_) {}

  const albumOnly = await applySaveTarget({
    savedFile,
    successfulDir,
    savedUri,
    fileName,
  });

  window.dispatchEvent(
    new CustomEvent("mori_file_saved", {
      detail: {
        url: sourceUrl || url,
        path: savedFile.path,
        uri: savedUri,
        title: effectiveTitle,
        albumOnly,
      },
    }),
  );

  if (!albumOnly && window.MoriMainBridge?.scanMediaFile) {
    try {
      window.MoriMainBridge.scanMediaFile(savedFile.path || savedUri);
    } catch (_) {}
  }

  const displayFolder = targetFolder.startsWith("/") ? targetFolder : `/${targetFolder}`;

  if (
    !window._moriPlaylistDownloading &&
    window.MoriMainBridge?.showCompleteNotification
  ) {
    try {
      window.MoriMainBridge.showCompleteNotification(
        effectiveTitle,
        albumOnly ? t("label-saved-to-album") : `${displayFolder}/${fileName}`,
      );
    } catch (_) {}
  }

  setTimeout(() => {
    if (btn && !window._moriPlaylistDownloading) {
      btn.disabled = false;
      const b = btn.querySelector(".dl-badge");
      if (b) {
        b.textContent =
          translations[currentLang]?.["label-download"] || "DOWNLOAD";
      } else {
        setButtonContent(btn, originalContent);
      }
    }
    if (!window._moriPlaylistDownloading) {
      progressContainer?.classList.add("hidden");
    }
  }, 2500);

  return {
    success: true,
    path: savedFile.path,
    uri: savedUri,
    title: effectiveTitle,
    albumOnly,
  };
}
