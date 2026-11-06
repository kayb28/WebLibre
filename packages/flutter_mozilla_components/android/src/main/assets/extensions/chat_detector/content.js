// Relay of the chat detector's background script.
//
// The background script watches response streams and knows only its own
// (extension) tab id. This script lives inside a page, so it is the one that
// can forward those events over a native port that the Kotlin side
// registered for this exact engine session — that is how the browser maps a
// stream to its WebLibre tab. It never reads the page, only relays.

const port = browser.runtime.connectNative("weblibreChatDetector");

browser.runtime.onMessage.addListener((message) => {
  if (!message || message.source !== "chatDetector") {
    return;
  }
  try {
    port.postMessage({ type: message.type, url: message.url });
  } catch (error) {
    // The port died with the page or was never connected: drop the event.
  }
});
