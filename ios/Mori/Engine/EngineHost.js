// Mori native engine host
// GNU General Public License v3.0 — (C) 2026 coflyn & contributors.
//
// Runs the shared scraper core (public/js/scrapers/bundle.js) inside a hidden
// WKWebView. Every network request the scrapers make is routed through
// `window.Capacitor.Plugins.CapacitorHttp`, which is implemented natively with
// URLSession (see EngineHTTP.swift). Nothing else of the old web UI is loaded.
(function () {
  "use strict";

  // ── Config store (replaces the web app's localStorage) ─────────────────
  const store = new Map([
    ["mori_request_timeout", "30"],
    ["mori_header_spoofing", "true"],
    ["mori_bypass_ssl", "false"],
    ["mori_force_ipv4", "false"],
    ["mori_doh", "off"],
    ["mori_user_agent", "default"],
  ]);
  const storage = {
    getItem: (k) => (store.has(k) ? store.get(k) : null),
    setItem: (k, v) => store.set(k, String(v)),
    removeItem: (k) => store.delete(k),
    clear: () => store.clear(),
    key: (i) => Array.from(store.keys())[i] ?? null,
    get length() {
      return store.size;
    },
  };

  function setConfig(cfg) {
    if (!cfg || typeof cfg !== "object") return;
    for (const [k, v] of Object.entries(cfg)) {
      if (v === null || v === undefined) store.delete(k);
      else store.set(k, String(v));
    }
  }

  const post = (name, payload) => window.webkit.messageHandlers[name].postMessage(payload);
  const log = (...args) => {
    try {
      post("moriLog", args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
    } catch (_) {}
  };

  // ── Native HTTP bridge (CapacitorHttp-compatible) ───────────────────────
  function normalizeBody(data) {
    if (data === undefined || data === null) return data;
    if (typeof URLSearchParams !== "undefined" && data instanceof URLSearchParams) return data.toString();
    if (typeof FormData !== "undefined" && data instanceof FormData) {
      const obj = {};
      for (const [k, v] of data.entries()) obj[k] = String(v);
      return obj;
    }
    if (typeof data === "object") {
      try {
        return JSON.parse(JSON.stringify(data));
      } catch (_) {
        return String(data);
      }
    }
    return typeof data === "string" ? data : String(data);
  }

  async function nativeRequest(method, o) {
    o = o || {};
    const payload = {
      method: (o.method || method || "GET").toUpperCase(),
      url: String(o.url || ""),
      headers: o.headers || {},
      responseType: o.responseType || "text",
      timeout: Number(o.connectTimeout || o.readTimeout || 30000),
      disableSSLValidation: !!o.disableSSLValidation,
    };
    if (o.params) payload.params = normalizeBody(o.params);
    if (o.data !== undefined) payload.data = normalizeBody(o.data);
    const res = await post("moriHttp", payload);
    return res;
  }

  const CapacitorHttp = {
    request: (o) => nativeRequest(o && o.method, o),
    get: (o) => nativeRequest("GET", o),
    post: (o) => nativeRequest("POST", o),
    put: (o) => nativeRequest("PUT", o),
    patch: (o) => nativeRequest("PATCH", o),
    delete: (o) => nativeRequest("DELETE", o),
  };

  window.Capacitor = {
    isNativePlatform: () => true,
    getPlatform: () => "ios",
    Plugins: { CapacitorHttp },
  };

  // ── Dependencies expected by the bundled core (window.__moriDeps) ───────
  const CHROME_DESKTOP_UA =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
  const CHROME_MOBILE_UA =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
  const CHROME_UA =
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36";
  const UA_PRESETS = { default: CHROME_UA, chrome: CHROME_UA, safari: CHROME_MOBILE_UA, desktop: CHROME_DESKTOP_UA };

  function getUserAgent() {
    const mode = storage.getItem("mori_user_agent") || "default";
    return UA_PRESETS[mode] || UA_PRESETS.default;
  }

  function getCookiesFromHeaders(headers) {
    const raw = (headers && (headers["Set-Cookie"] || headers["set-cookie"])) || "";
    if (!raw) return "";
    if (Array.isArray(raw)) return raw.map((c) => c.split(";")[0]).join("; ");
    return raw
      .split(/,(?=\s*[^;,=]+=[^;]*)/)
      .map((c) => c.trim().split(";")[0])
      .filter((c) => c && c.includes("="))
      .join("; ");
  }

  function serializeData(obj) {
    return Object.keys(obj)
      .map((key) => encodeURIComponent(key) + "=" + encodeURIComponent(obj[key]))
      .join("&");
  }

  function decodeSnapSave(data) {
    try {
      const regex = /eval\(function\(h,u,n,t,e,r\)\{.*?\}\("(.*?)",(\d+),"(.*?)",(\d+),(\d+),(\d+)\)\)/;
      const match = data.match(regex);
      if (match) {
        const h = match[1],
          n = match[3],
          t = parseInt(match[4]),
          e = parseInt(match[5]);
        const delimiter = n[e],
          parts = h.split(delimiter);
        let decoded = "";
        for (const s of parts) {
          if (s === "") continue;
          let val = 0;
          for (let j = 0; j < s.length; j++) val += n.indexOf(s[j]) * Math.pow(e, s.length - 1 - j);
          decoded += String.fromCharCode(val - t);
        }
        return decodeURIComponent(escape(decoded));
      }
      return data;
    } catch (_) {
      return data;
    }
  }

  function extractFinalUrl(input) {
    if (!input) return null;
    let raw = input.trim().replace(/^["'\\]+|["'\\]+$/g, ""),
      isRender = false;
    if (raw.includes("get_progressApi") || raw.includes("get_progress")) {
      isRender = true;
      const tokenMatch = raw.match(/token=([^&'"]+)/);
      if (tokenMatch) raw = tokenMatch[1];
    }
    if (raw.includes(".") && !raw.startsWith("http")) {
      try {
        const payloadPart = raw.split(".")[1];
        if (payloadPart) {
          const payload = JSON.parse(atob(payloadPart));
          if (payload.video_url) return { url: payload.video_url, isRender: true };
          if (payload.url) return { url: payload.url, isRender: false };
        }
      } catch (_) {}
    }
    if (raw.startsWith("//")) return { url: "https:" + raw, isRender };
    if (raw.startsWith("/")) return { url: "https://snapsave.app" + raw, isRender };
    return { url: raw, isRender };
  }

  function cleanUrl(url) {
    if (!url) return "";
    try {
      const u = new URL(url);
      ["igsh", "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "s", "t", "si", "feature"].forEach((p) =>
        u.searchParams.delete(p),
      );
      const h = u.hostname;
      if (h.includes("tiktok.com") || h.includes("tt.site")) {
        u.search = "";
      } else if (h.includes("youtube.com") || h.includes("youtu.be")) {
        if (h.includes("youtube.com") && u.searchParams.has("v")) {
          const v = u.searchParams.get("v");
          u.search = "";
          u.searchParams.set("v", v);
        }
      } else if (/xiaohongshu\.com|rednote\.com|xhslink\.com|xhslink\.cn/.test(h)) {
        // keep xsec_token
      } else if (/terabox|1024tera|nephobox|4funbox|mirrobox|momerybox|tibibox/.test(h)) {
        // keep surl
      } else if (!h.includes("facebook.com")) {
        if (!u.searchParams.has("id") && !u.searchParams.has("story_fbid")) u.search = "";
      }
      return u.href.replace(/\/$/, "");
    } catch (_) {
      return url.split("?")[0].replace(/\/$/, "");
    }
  }

  function extractCleanUrl(text) {
    if (!text || typeof text !== "string") return "";
    const match = text.match(/https?:\/\/[^\s]+/);
    let clean = match ? match[0] : text.trim();
    if (!clean) return "";
    if (!clean.startsWith("http://") && !clean.startsWith("https://")) clean = "https://" + clean;
    return cleanUrl(clean);
  }

  const utils = {
    CHROME_UA,
    CHROME_DESKTOP_UA,
    CHROME_MOBILE_UA,
    SAFARI_MOBILE_UA: CHROME_MOBILE_UA,
    UA_PRESETS,
    CapacitorHttp,
    getUserAgent,
    getCookiesFromHeaders,
    serializeData,
    decodeSnapSave,
    extractFinalUrl,
    cleanUrl,
    extractCleanUrl,
    getCleanUrl: extractCleanUrl,
  };
  window.__moriDeps = {
    utils,
    urlUtils: { cleanUrl, extractCleanUrl, getCleanUrl: extractCleanUrl },
    core: { t: (k) => k, currentLang: "en" },
  };

  // ── Core loader ─────────────────────────────────────────────────────────
  let core = null;
  function boot(bundleText) {
    core = null;
    window.__MoriCoreScrapers = undefined;
    const fn = new Function(
      "localStorage",
      bundleText +
        "\nreturn typeof __MoriCoreScrapers !== 'undefined' ? __MoriCoreScrapers : (typeof window !== 'undefined' ? window.__MoriCoreScrapers : null);",
    );
    const mod = fn(storage);
    if (!mod || typeof mod.scrapeTikTok !== "function") throw new Error("Scraper core failed to initialize");
    core = mod;
    window.__MoriCoreScrapers = mod;
    return Object.keys(mod).filter((k) => k.startsWith("scrape")).length;
  }

  function requireCore() {
    if (!core) throw new Error("Scraper engine is not ready");
    return core;
  }

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // ── Platform routing (ported from modules/download.js) ──────────────────
  const TERABOX = /terabox|1024tera|nephobox|4funbox|mirrobox|momerybox|tibibox/;
  function platformOf(url) {
    const u = url.toLowerCase();
    if (u.includes("tiktok.com") || u.includes("tt.site")) return "tiktok";
    if (u.includes("instagram.com")) return "instagram";
    if (u.includes("youtube.com") || u.includes("youtu.be")) return "youtube";
    if (
      u.includes("twitter.com") ||
      /(?:^|[/.])x\.com(?:[/?#:]|$)/i.test(u) ||
      u.includes("fixupx.com") ||
      u.includes("fxtwitter.com") ||
      u.includes("vxtwitter.com")
    )
      return "twitter";
    if (u.includes("spotify.com")) return "spotify";
    if (u.includes("pinterest.com") || u.includes("pin.it")) return "pinterest";
    if (u.includes("music.apple.com")) return "applemusic";
    if (u.includes("facebook.com") || u.includes("fb.watch")) return "facebook";
    if (u.includes("xiaohongshu.com") || u.includes("rednote.com") || u.includes("xhslink.com") || u.includes("xhslink.cn"))
      return "rednote";
    if (u.includes("douyin.com")) return "douyin";
    if (u.includes("bilibili.com") || u.includes("b23.tv") || u.includes("bili.im") || u.includes("bilibili.tv")) return "bilibili";
    if (u.includes("threads.net") || u.includes("threads.com")) return "threads";
    if (u.includes("bandcamp.com")) return "bandcamp";
    if (u.includes("pixiv.net")) return "pixiv";
    if (u.includes("reddit.com") || u.includes("redd.it")) return "reddit";
    if (TERABOX.test(u)) return "terabox";
    return null;
  }

  // [server1, server2] per platform with a source switch
  const SOURCES = {
    tiktok: ["tiktokio", "tikdownloader"],
    instagram: ["indown", "savevid"],
    youtube: ["gg", "mobi"],
    twitter: ["tvd", "savetwt"],
    spotify: ["spotidown", "soundloaders"],
  };

  function setSource(c, platform, src) {
    switch (platform) {
      case "tiktok":
        return c.setTikTokSource(src);
      case "instagram":
        return c.setInstagramSource(src);
      case "youtube":
        return c.setYouTubeSource(src);
      case "twitter":
        return c.setTwitterSource(src);
      case "spotify":
        return c.setSpotifySource(src);
    }
  }

  async function scrapeDouyin(c, url) {
    const originalUrl = url;
    let targetUrl = url;
    if (url.includes("v.douyin.com") || url.includes("/share/slides/")) {
      try {
        let resolvedUrl = url;
        if (url.includes("v.douyin.com")) {
          const fetchRes = await c.scraperFetch(
            {
              url,
              method: "GET",
              headers: {
                "User-Agent":
                  "Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1",
                Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
              },
              rawResponse: true,
            },
            "Douyin Resolver",
          );
          if (fetchRes && fetchRes.url) resolvedUrl = fetchRes.url;
        }
        const slidesMatch = resolvedUrl.match(/share\/slides\/([0-9]{15,22})/i);
        if (slidesMatch && slidesMatch[1]) targetUrl = "https://www.iesdouyin.com/share/video/" + slidesMatch[1] + "/";
        else if (resolvedUrl && resolvedUrl !== url) targetUrl = resolvedUrl;
      } catch (e) {
        log("Douyin resolver warning:", String(e && e.message));
      }
    }
    let res;
    try {
      res = await c.scrapeDouyin(targetUrl);
      if (!res || !res.status) {
        await sleep(400);
        res = await c.scrapeDouyin(targetUrl);
      }
    } catch (_) {
      await sleep(400);
      res = await c.scrapeDouyin(targetUrl);
    }
    if (res) {
      if (res.result) res.result.sourceUrl = originalUrl;
      res.sourceUrl = originalUrl;
    }
    return res;
  }

  async function runScraper(c, platform, url) {
    switch (platform) {
      case "tiktok":
        return c.scrapeTikTok(url);
      case "instagram":
        return c.scrapeInstagram(url);
      case "youtube":
        return c.scrapeYouTube(url);
      case "twitter":
        return c.scrapeTwitter(url);
      case "spotify":
        return c.scrapeSpotify(url);
      case "pinterest":
        return c.scrapePinterest(url);
      case "applemusic":
        return c.scrapeAppleMusic(url);
      case "facebook":
        return c.scrapeFacebook(url);
      case "rednote":
        return c.scrapeRedNote(url);
      case "douyin":
        return scrapeDouyin(c, url);
      case "bilibili":
        return c.scrapeBilibili(url);
      case "threads":
        return c.scrapeThreads(url);
      case "bandcamp":
        return c.scrapeBandcamp(url);
      case "pixiv":
        return c.scrapePixiv(url);
      case "reddit":
        return c.scrapeReddit(url);
      case "terabox":
        return c.scrapeTeraBox(url);
    }
    return { status: false, message: "URL not supported yet." };
  }

  function isYouTubePlaylist(url) {
    const playlistMatch = url.match(/[?&]list=([^"&?\/\s]+)/i);
    const videoMatch = url.match(
      /(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?|shorts|live)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})/i,
    );
    return !!(playlistMatch && playlistMatch[1]) && (!(videoMatch && videoMatch[1]) || url.includes("/playlist"));
  }

  /**
   * opts.source  explicit source key chosen by the user ("" = none)
   * opts.prefer  "ask" | "server1" | "server2" | "auto"  ("auto" = server1 with server2 fallback, used by batch)
   */
  async function analyze(rawUrl, opts) {
    opts = opts || {};
    setConfig(opts.config);
    const c = requireCore();
    const trimmed = String(rawUrl || "").trim();
    // Keep raw input for YouTube (list= params) — cleanUrl only strips trackers
    const url = extractCleanUrl(trimmed) || trimmed;
    const platform = platformOf(url);
    if (!platform) return { status: false, message: "URL not supported yet.", platform: null };

    let data;
    try {
      const sources = SOURCES[platform];
      if (sources) {
        let src = opts.source || null;
        const prefer = opts.prefer || "ask";
        if (!src) {
          if (prefer === "server1" || prefer === "auto") src = sources[0];
          else if (prefer === "server2") src = sources[1];
        }
        if (platform === "youtube" && isYouTubePlaylist(url)) src = "gg";
        setSource(c, platform, src);
        data = await runScraper(c, platform, url);
        if (data && data.requireSource) {
          return { status: false, requireSource: true, platform, sources };
        }
        if (prefer === "auto" && !opts.source && (!data || !data.status) && platform !== "youtube") {
          setSource(c, platform, sources[1]);
          data = await runScraper(c, platform, url);
        }
      } else {
        data = await runScraper(c, platform, url);
      }
    } catch (e) {
      data = { status: false, message: (e && e.message) || String(e) };
    }

    if (!data) data = { status: false, message: "Unknown error occurred." };
    data.platform = platform;
    data.inputUrl = url;
    if (data.status && data.result) {
      if (!data.result.sourceUrl) data.result.sourceUrl = url;
      if (!Array.isArray(data.result.downloads)) data.result.downloads = [];
    }
    return data;
  }

  // ── Download link resolution (ported from downloader/resolver.js) ───────
  const cancelled = {};
  function needsAsyncResolving(url) {
    return (
      (url.includes("ytdown") ||
        url.includes("worker") ||
        url.includes("youtube_resolve:") ||
        url.includes("ytmp3gg_resolve:") ||
        url.includes("soundloaders_resolve:") ||
        url.includes("spotidown_resolve:") ||
        url.includes("applemusic_resolve:") ||
        (url.includes("token=") && url.includes("snapsave"))) &&
      !url.toLowerCase().match(/\.(mp4|mp3|m4a|zip|pdf|jpg|jpeg|png|webp)(\?|$)/)
    );
  }

  async function resolve(url, taskId, opts) {
    opts = opts || {};
    setConfig(opts.config);
    const c = requireCore();
    const scraperFetch = c.scraperFetch;
    if (!needsAsyncResolving(url)) return { url, cancelled: false };
    delete cancelled[taskId];
    const checkCancelled = () => !!cancelled[taskId];
    const updateProgress = (pct, text) => {
      try {
        post("moriProgress", { id: taskId, pct: Number(pct) || 0, text: String(text || "") });
      } catch (_) {}
    };
    try {
      const out = await resolveDownloadUrl({ url, scraperFetch, updateProgress, checkCancelled });
      return out;
    } finally {
      delete cancelled[taskId];
    }
  }

  function cancel(taskId) {
    cancelled[taskId] = true;
  }

  async function resolveDownloadUrl({ url, scraperFetch, updateProgress, checkCancelled }) {
    let actualDownloadUrl = url;

    if (url.startsWith("applemusic_resolve:")) {
      const payloadStr = url.replace("applemusic_resolve:", "");
      let foundLink = "";
      let lastErr = null;
      for (let attempt = 1; attempt <= 3; attempt++) {
        if (checkCancelled()) return { cancelled: true };
        try {
          if (attempt > 1) {
            updateProgress(20, `Resolving Apple Music track (Retry ${attempt}/3)...`);
            await sleep(1500 * attempt);
          }
          const res = await scraperFetch({
            method: "POST",
            url: "https://aplmate.com/action/track",
            headers: {
              "Content-Type": "application/x-www-form-urlencoded",
              "User-Agent": CHROME_UA,
              "X-Requested-With": "XMLHttpRequest",
              Referer: "https://aplmate.com/",
              Origin: "https://aplmate.com",
            },
            data: payloadStr,
          });
          const dd = typeof res === "string" ? JSON.parse(res) : res;
          let dlHtml = (typeof dd === "object" ? dd && dd.data : dd) || "";
          if (typeof dlHtml !== "string") dlHtml = JSON.stringify(dlHtml);
          const doc = new DOMParser().parseFromString(dlHtml, "text/html");
          doc.querySelectorAll("a").forEach((a) => {
            const href = a.getAttribute("href");
            const text = a.textContent.trim();
            if (href && (href.includes("/dl?token=") || a.classList.contains("abutton"))) {
              if (href.includes("ko-fi.com") || href.includes("premium.html")) return;
              if (text.toLowerCase().includes("another song") || text.toLowerCase().includes("cover") || href.includes("cover="))
                return;
              if (!foundLink) foundLink = href.startsWith("http") ? href : "https://aplmate.com" + href;
            }
          });
          if (foundLink) break;
        } catch (err) {
          lastErr = err;
        }
      }
      if (!foundLink) throw lastErr || new Error("Could not resolve Apple Music download link");
      actualDownloadUrl = foundLink;
    } else if (url.startsWith("spotidown_resolve:")) {
      updateProgress(20, "Resolving Spotify track...");
      const parts = url.replace("spotidown_resolve:", "").split("|||");
      const payloadStr = parts[0];
      let cookiesStr = parts[1] ? decodeURIComponent(parts[1]) : "";
      let foundLink = "";
      let lastErr = null;
      for (let attempt = 1; attempt <= 3; attempt++) {
        if (checkCancelled()) return { cancelled: true };
        try {
          if (attempt > 1 || !cookiesStr) {
            if (attempt > 1) {
              updateProgress(20, `Resolving Spotify track (Retry ${attempt}/3)...`);
              await sleep(1500 * attempt);
            }
            try {
              const trackUrl = new URLSearchParams(payloadStr).get("base") || "https://open.spotify.com";
              const rSession = await scraperFetch({
                url: "https://spotidown.app/action",
                method: "POST",
                data: `url=${encodeURIComponent(trackUrl)}&g-recaptcha-response=dummy_token`,
                headers: {
                  "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                  "User-Agent": getUserAgent(),
                  "X-Requested-With": "XMLHttpRequest",
                  Origin: "https://spotidown.app",
                  Referer: "https://spotidown.app/",
                },
                rawResponse: true,
              });
              const freshCookies = getCookiesFromHeaders(rSession.headers);
              if (freshCookies) cookiesStr = freshCookies;
            } catch (_) {}
          }
          const reqHeaders = {
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "User-Agent": getUserAgent(),
            "X-Requested-With": "XMLHttpRequest",
            Referer: "https://spotidown.app/",
            Origin: "https://spotidown.app",
          };
          if (cookiesStr) reqHeaders["Cookie"] = cookiesStr;
          const res = await scraperFetch(
            { url: "https://spotidown.app/action/track", method: "POST", headers: reqHeaders, data: payloadStr, rawResponse: true },
            "SpotiDown",
          );
          let dd = res && res.data !== undefined ? res.data : res;
          if (typeof dd === "string") {
            try {
              dd = JSON.parse(dd);
            } catch (_) {}
          }
          if (dd && dd.error && dd.message) {
            lastErr = new Error(dd.message);
            cookiesStr = "";
          }
          let dlHtml = (typeof dd === "object" ? (dd && (dd.data || dd.html)) : dd) || "";
          if (typeof dlHtml !== "string") dlHtml = JSON.stringify(dlHtml);
          const doc = new DOMParser().parseFromString(dlHtml, "text/html");
          doc.querySelectorAll("a").forEach((a) => {
            const href = a.getAttribute("href");
            const text = a.textContent.trim();
            if (
              href &&
              href.startsWith("http") &&
              !href.includes("premium.html") &&
              !href.includes("ko-fi.com") &&
              text !== "Download Another Song"
            ) {
              if (!foundLink) foundLink = href;
            }
          });
          if (foundLink) break;
        } catch (err) {
          lastErr = err;
        }
      }
      if (!foundLink) throw lastErr || new Error("Could not resolve SpotiDown download link");
      updateProgress(50, "Starting MP3 download...");
      actualDownloadUrl = foundLink;
    } else if (url.startsWith("soundloaders_resolve:")) {
      updateProgress(20, "Resolving Spotify track...");
      const parts = url.replace("soundloaders_resolve:", "").split("|||");
      const dataVal = parts[0];
      const tokenVal = parts[1];
      const baseVal = parts[2] ? decodeURIComponent(parts[2]) : "";
      const BASE = "https://spotimate.app";
      const createMultipartBody = (fields) => {
        const boundary = "----WebKitFormBoundary" + Math.random().toString(36).substring(2);
        let body = "";
        for (const [k, v] of Object.entries(fields)) {
          if (v !== undefined && v !== null) body += `--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`;
        }
        body += `--${boundary}--\r\n`;
        return { body, contentType: `multipart/form-data; boundary=${boundary}` };
      };
      let matchLink = "";
      let lastErr = null;
      for (let attempt = 1; attempt <= 3; attempt++) {
        if (checkCancelled()) return { cancelled: true };
        try {
          if (attempt > 1) {
            updateProgress(20, `Resolving Spotify track (Retry ${attempt}/3)...`);
            await sleep(1500 * attempt);
          }
          const mp = createMultipartBody({
            data: dataVal,
            token: tokenVal,
            track_token: tokenVal,
            ...(baseVal ? { base: baseVal } : {}),
          });
          const res = await scraperFetch(
            {
              url: BASE + "/action/track",
              method: "POST",
              headers: { "Content-Type": mp.contentType, "User-Agent": getUserAgent(), Referer: BASE + "/en1", Origin: BASE },
              data: mp.body,
              rawResponse: true,
            },
            "Soundloaders",
          );
          let dd = res && res.data !== undefined ? res.data : res;
          if (typeof dd === "string") {
            try {
              dd = JSON.parse(dd);
            } catch (_) {}
          }
          const dlHtml = (typeof dd === "object" ? (dd && (dd.html || dd.data)) : dd) || "";
          const match =
            String(dlHtml).match(/href=["'](https:\/\/(?:dl\.spotimate\.app|dl\.soundloaders\.app)[^"']+)["']/) ||
            String(dlHtml).match(/href=["'](https:\/\/[^"']*(?:cdnv1|\/v1\?token=)[^"']+)["']/);
          if (match && match[1]) {
            matchLink = match[1];
            break;
          }
        } catch (err) {
          lastErr = err;
        }
      }
      if (!matchLink) throw lastErr || new Error("Could not resolve Soundloaders download link");
      updateProgress(50, "Starting MP3 download...");
      actualDownloadUrl = matchLink;
    } else if (url.startsWith("youtube_resolve:") || url.startsWith("ytmp3gg_resolve:")) {
      const raw = url.startsWith("youtube_resolve:") ? url.replace("youtube_resolve:", "") : url.replace("ytmp3gg_resolve:", "");
      const parts = raw.split("|||");
      const ytId = parts[0];
      const format = parts[1] || "mp3";
      const quality = parts[2] || "128";
      let downloadUrl = null;

      try {
        updateProgress(10, "Converting with ytmp3.mobi...");
        const mobiHeaders = {
          Origin: "https://ytmp3.mobi",
          Referer: "https://ytmp3.mobi/en8/",
          "User-Agent": getUserAgent(),
          "Sec-Fetch-Dest": "empty",
          "Sec-Fetch-Mode": "cors",
          "Sec-Fetch-Site": "cross-site",
          Accept: "*/*",
        };
        const initData = await scraperFetch(
          { url: `https://a.ymcdn.org/api/v1/init?p=y&23=1llum1n471&_=${Math.random()}`, headers: mobiHeaders },
          "ytmp3.mobi Init",
        );
        if (initData && !initData.error && initData.convertURL) {
          let convData = await scraperFetch(
            { url: `${initData.convertURL}&v=${ytId}&f=${format}&_=${Math.random()}`, headers: mobiHeaders },
            "ytmp3.mobi Convert",
          );
          while (convData && convData.redirect > 0 && convData.redirectURL) {
            convData = await scraperFetch(
              { url: `${convData.redirectURL}&v=${ytId}&f=${format}&_=${Math.random()}`, headers: mobiHeaders },
              "ytmp3.mobi Redirect",
            );
          }
          if (convData && !convData.error) {
            let dlUrl = convData.downloadURL;
            const progUrl = convData.progressURL;
            let progress = 0;
            let attempts = 0;
            const maxAttempts = 30;
            while (progress < 3 && attempts < maxAttempts) {
              if (checkCancelled()) return { cancelled: true };
              await sleep(1500);
              if (!progUrl) break;
              const progData = await scraperFetch({ url: `${progUrl}&_=${Math.random()}`, headers: mobiHeaders }, "ytmp3.mobi Progress");
              if (!progData || progData.error) break;
              progress = progData.progress;
              if (progData.downloadURL) dlUrl = progData.downloadURL;
              updateProgress(
                Math.min(90, 10 + Math.round(((attempts + 1) / maxAttempts) * 80)),
                `Converting with ytmp3... (${attempts + 1}/${maxAttempts})`,
              );
              if (progress >= 3) break;
              attempts++;
            }
            if (dlUrl && progress >= 3) {
              if (dlUrl.startsWith("//")) dlUrl = "https:" + dlUrl;
              if (dlUrl.startsWith("/")) dlUrl = "https://ytmp3.mobi" + dlUrl;
              downloadUrl = dlUrl;
            }
          }
        }
      } catch (mobiErr) {
        log("ytmp3.mobi engine failed, falling back to convert1s:", String(mobiErr && mobiErr.message));
      }

      if (!downloadUrl && !checkCancelled()) {
        try {
          updateProgress(15, "Converting with ytmp3.gg...");
          const headers = {
            Origin: "https://media.ytmp3.gg",
            Referer: "https://media.ytmp3.gg/",
            "User-Agent": getUserAgent(),
            Accept: "application/json, text/plain, */*",
            "Content-Type": "application/json",
          };
          let conv = null;
          for (let initAttempt = 1; initAttempt <= 2; initAttempt++) {
            if (checkCancelled()) return { cancelled: true };
            try {
              if (initAttempt > 1) await sleep(1500);
              let parsedConv = await scraperFetch({
                url: "https://hub.convert1s.com/api/download",
                method: "POST",
                headers,
                data: JSON.stringify({
                  url: `https://www.youtube.com/watch?v=${ytId}`,
                  os: "macos",
                  output: { type: format === "mp4" ? "video" : "audio", format, quality },
                  audio: { bitrate: "128k" },
                }),
              });
              if (typeof parsedConv === "string") parsedConv = JSON.parse(parsedConv);
              if (parsedConv && !parsedConv.error && parsedConv.statusUrl) {
                conv = parsedConv;
                break;
              }
            } catch (_) {}
          }
          if (conv && conv.statusUrl) {
            let pollCount = 0;
            const maxPolls = 30;
            while (!downloadUrl && pollCount < maxPolls) {
              if (checkCancelled()) return { cancelled: true };
              updateProgress(Math.min(90, 20 + pollCount * 2), `Converting... (${pollCount + 1}/${maxPolls})`);
              await sleep(1500);
              try {
                const pollData = await scraperFetch({
                  url: conv.statusUrl,
                  headers: {
                    Origin: "https://media.ytmp3.gg",
                    Referer: "https://media.ytmp3.gg/",
                    "User-Agent": getUserAgent(),
                    Accept: "application/json, text/plain, */*",
                  },
                });
                const poll = typeof pollData === "string" ? JSON.parse(pollData) : pollData;
                if (poll && poll.status === "completed" && poll.downloadUrl) {
                  downloadUrl = poll.downloadUrl;
                  break;
                }
                if (poll && (poll.status === "error" || poll.status === "failed")) break;
              } catch (_) {}
              pollCount++;
            }
          }
        } catch (ggErr) {
          log("convert1s engine failed:", String(ggErr && ggErr.message));
        }
      }

      if (checkCancelled()) return { cancelled: true };
      if (!downloadUrl) throw new Error("Failed to convert YouTube track. All download servers were unreachable.");
      actualDownloadUrl = downloadUrl;
    } else {
      // SnapSave tokens or generic worker resolves
      let resolved = false;
      let pollCount = 0;
      const maxPolls = 20;
      while (!resolved && pollCount < maxPolls) {
        if (checkCancelled()) return { cancelled: true };
        updateProgress(Math.min(90, 10 + pollCount * 4), `Resolving URL... (${pollCount + 1}/${maxPolls})`);
        try {
          const statusRes = await scraperFetch({ url: actualDownloadUrl, rawResponse: true }, "Resolver");
          if (statusRes && statusRes.data) {
            let data = statusRes.data;
            if (typeof data === "string") {
              try {
                data = JSON.parse(data);
              } catch (_) {}
            }
            if (data.fileUrl || data.url || data.download_url) {
              actualDownloadUrl = data.fileUrl || data.url || data.download_url;
              resolved = true;
            } else if (data.status === "success" && data.download_url) {
              actualDownloadUrl = data.download_url;
              resolved = true;
            } else if (typeof data === "string" && data.includes('"fileUrl":')) {
              const match = data.match(/"fileUrl"\s*:\s*"([^"]+)"/);
              if (match) {
                actualDownloadUrl = match[1];
                resolved = true;
              }
            }
          }
        } catch (err) {
          log("Poll attempt failed", String(err && err.message));
        }
        if (!resolved) {
          pollCount++;
          await sleep(1500);
        }
      }
      if (!resolved) throw new Error("Unable to resolve download URL");
    }

    return { url: actualDownloadUrl, cancelled: false };
  }

  window.MoriEngine = {
    boot,
    setConfig,
    analyze,
    resolve,
    cancel,
    needsAsyncResolving,
    platformOf,
    extractCleanUrl,
    isReady: () => !!core,
  };
})();
