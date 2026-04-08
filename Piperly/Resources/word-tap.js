(function () {
  var WORD_CLASS = "piperly-word";

  function wrapTextNode(textNode) {
    var text = textNode.textContent;
    if (!text.trim()) return;

    var fragment = document.createDocumentFragment();
    var parts = text.split(/(\s+)/);
    parts.forEach(function (part) {
      if (/\s+/.test(part)) {
        fragment.appendChild(document.createTextNode(part));
      } else if (part.length > 0) {
        var span = document.createElement("span");
        span.className = WORD_CLASS;
        span.textContent = part;
        fragment.appendChild(span);
      }
    });
    textNode.parentNode.replaceChild(fragment, textNode);
  }

  function wrapAllWords() {
    var walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: function (node) {
          var tag = node.parentElement.tagName;
          if (tag === "SCRIPT" || tag === "STYLE")
            return NodeFilter.FILTER_REJECT;
          if (node.parentElement.classList.contains(WORD_CLASS))
            return NodeFilter.FILTER_REJECT;
          if (!node.textContent.trim()) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        },
      },
    );

    var textNodes = [];
    while (walker.nextNode()) textNodes.push(walker.currentNode);
    textNodes.forEach(wrapTextNode);
  }

  var style = document.createElement("style");
  style.textContent =
    "." +
    WORD_CLASS +
    " { cursor: pointer; border-radius: 3px; transition: background 0.15s; }" +
    "." +
    WORD_CLASS +
    ".tapped { background: var(--piperly-highlight, rgba(124, 212, 200, 0.3)); }";
  document.head.appendChild(style);

  document.addEventListener("click", function (e) {
    var target = e.target;
    if (target.classList.contains(WORD_CLASS)) {
      var raw = target.textContent;
      var clean = raw.replace(
        /^[^a-zA-Z\u00C0-\u024F]+|[^a-zA-Z\u00C0-\u024F]+$/g,
        "",
      );
      if (clean.length === 0) return;

      target.classList.add("tapped");
      setTimeout(function () {
        target.classList.remove("tapped");
      }, 400);

      window.webkit.messageHandlers.wordTapped.postMessage({
        word: clean,
        raw: raw,
        rect: target.getBoundingClientRect(),
      });
    }
  });

  wrapAllWords();

  var observer = new MutationObserver(function (mutations) {
    mutations.forEach(function (mutation) {
      mutation.addedNodes.forEach(function (node) {
        if (
          node.nodeType === Node.ELEMENT_NODE &&
          !node.classList.contains(WORD_CLASS)
        ) {
          var walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
          var textNodes = [];
          while (walker.nextNode()) textNodes.push(walker.currentNode);
          textNodes.forEach(wrapTextNode);
        }
      });
    });
  });
  observer.observe(document.body, { childList: true, subtree: true });
})();
