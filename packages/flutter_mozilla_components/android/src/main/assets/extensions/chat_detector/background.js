// WebLibre chat generation detector.
//
// Watches response streams at the engine level and reports, per tab, when a
// chat-like stream starts and ends. A "generation" here is any POSTed
// server-sent response that stays open while content is produced — the shape
// every mainstream chat site uses to stream answers, since the prompt travels
// in the request body — plus a small list of recognized completion endpoints
// as a fallback for sites that stream in other shapes. Streams that open
// without a POST body (auto-reconnecting GET notification listeners and their
// kin) are not generations: they live as long as the tab and would otherwise
// pin the keep-alive service — and with it the CPU — open forever.
//
// Reports travel background -> content script -> native port, so the Kotlin
// side can attribute them to the exact engine session (the content script's
// port is registered per session, the same way readability-extract does it).

// Response streams we treat as a generation when their content type matches.
const STREAM_CONTENT_TYPES = ["text/event-stream"];

// Recognized completion endpoints (method POST), as a fallback for streams
// whose headers do not identify them. Matched against the URL path only.
const KNOWN_STREAM_PATHS = [/\/backend-api\/conversation(\/|$|\?)/, /\/(chat\/)?completions(\/|$|\?)/, /\/conversation\/(stream|events)/];

// A stream nobody reported closed is only trusted for this long; a tab with
// an old lingering stream must not hold the keep-alive service hostage.
const MAX_STREAM_MS = 10 * 60 * 1000;

// Listener filter shared by all three watchers. Generation streams can only
// be XHR, fetch or EventSource requests — in Firefox all three arrive as type
// "xmlhttprequest" — so restricting the filter to that type keeps every
// image, script, stylesheet, font and media request of every tab out of this
// background page entirely, instead of paying the dispatch and header
// marshalling cost for every single request on every page.
const STREAM_REQUEST_FILTER = {
  urls: ["http://*/*", "https://*/*"],
  types: ["xmlhttprequest"],
};

// requestId -> { tabId: number, url: string, since: number }
const tracked = new Map();

function headerValue(headers, name) {
  for (const header of headers || []) {
    if ((header.name || "").toLowerCase() === name) {
      return (header.value || "").toLowerCase();
    }
  }
  return "";
}

function looksLikeGeneration(details) {
  // Generations are POST requests: the prompt travels in the request body.
  // Notification and presence listeners are GET streams that a site holds
  // open (and reopens, in a loop, whenever they drop) for as long as the
  // tab lives; mistaking them for generations kept the keep-alive service
  // running around the clock on chat tabs — the heat report.
  if (details.method !== "POST") {
    return false;
  }

  const contentType = headerValue(details.responseHeaders, "content-type");
  if (STREAM_CONTENT_TYPES.some((type) => contentType.includes(type))) {
    return true;
  }

  // Fallback for known endpoints: chunked JSON completions whose content
  // type is not event-stream (some sites stream plain JSON). The request
  // had no content-length header, so the body arrives as it is produced.
  if (headerValue(details.responseHeaders, "content-length") !== "") {
    return false;
  }
  const afterHost = details.url.split("://", 2)[1] || "";
  const firstSlash = afterHost.indexOf("/");
  const pathOnly = firstSlash >= 0 ? afterHost.slice(firstSlash) : "/";
  return KNOWN_STREAM_PATHS.some((pattern) => pattern.test(pathOnly));
}

function report(tabId, url, type) {
  // The content script of that tab relays the event over its own native
  // port, which the Kotlin side registered for this exact session.
  browser.tabs.sendMessage(tabId, { source: "chatDetector", type: type, url: url }).catch(() => {
    // No receiver yet (content script not injected, or the tab is gone):
    // nothing to attribute the stream to.
  });
}

browser.webRequest.onHeadersReceived.addListener(
  (details) => {
    if (details.tabId < 0 || !details.url.startsWith("http")) {
      return;
    }
    if (!looksLikeGeneration(details)) {
      return;
    }
    tracked.set(details.requestId, {
      tabId: details.tabId,
      url: details.url,
      since: Date.now(),
    });
    report(details.tabId, details.url, "started");
  },
  STREAM_REQUEST_FILTER,
  ["responseHeaders"]
);

function onStreamEnd(details) {
  const entry = tracked.get(details.requestId);
  if (!entry) {
    return;
  }
  tracked.delete(details.requestId);
  report(entry.tabId, entry.url, "ended");
}

browser.webRequest.onCompleted.addListener(onStreamEnd, STREAM_REQUEST_FILTER);
browser.webRequest.onErrorOccurred.addListener(onStreamEnd, STREAM_REQUEST_FILTER);

// Sweep streams nobody reported closed, so a tab cannot stay "generating"
// forever because of a long-lived notification stream.
setInterval(() => {
  const now = Date.now();
  for (const [requestId, entry] of tracked) {
    if (now - entry.since > MAX_STREAM_MS) {
      tracked.delete(requestId);
      report(entry.tabId, entry.url, "ended");
    }
  }
}, 60 * 1000);
