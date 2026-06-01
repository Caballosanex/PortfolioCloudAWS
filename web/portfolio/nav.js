(function () {
  'use strict';

  function initNav() {
    var btn = document.querySelector('.nav-toggle');
    var menu = document.querySelector('.nav-links');
    if (!btn || !menu) return;

    function isMobile() {
      return window.matchMedia('(max-width:768px)').matches;
    }

    function open() {
      menu.classList.add('open');
      btn.setAttribute('aria-expanded', 'true');
    }

    function close() {
      menu.classList.remove('open');
      btn.setAttribute('aria-expanded', 'false');
    }

    btn.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      if (menu.classList.contains('open')) {
        close();
      } else {
        open();
      }
    });

    menu.addEventListener('click', function (e) {
      var t = e.target;
      while (t && t !== menu) {
        if (t.tagName === 'A') {
          close();
          return;
        }
        t = t.parentNode;
      }
    });

    document.addEventListener('click', function (e) {
      if (!menu.classList.contains('open')) return;
      if (menu.contains(e.target) || btn.contains(e.target)) return;
      close();
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && menu.classList.contains('open')) {
        close();
        btn.focus();
      }
    });

    window.addEventListener('resize', function () {
      if (!isMobile()) close();
    });
  }

  function initFilters() {
    var pills = document.querySelectorAll('.stack-pill[data-filter]');
    var cards = document.querySelectorAll('.project-card[data-tech]');
    var statusEl = document.querySelector('[data-filter-status]');
    var countEl = document.querySelector('[data-filter-count]');
    var emptyEl = document.querySelector('[data-filter-empty]');
    var clearBtns = document.querySelectorAll('[data-filter-clear]');

    if (!pills.length || !cards.length) return;

    pills.forEach(function (pill) {
      pill.setAttribute('aria-pressed', 'false');
    });

    var active = new Set();

    function getCardTechs(card) {
      return (card.getAttribute('data-tech') || '').toLowerCase().split(/\s+/).filter(Boolean);
    }

    function cardMatches(card) {
      if (active.size === 0) return true;
      var techs = getCardTechs(card);
      for (var i = 0; i < techs.length; i++) {
        if (active.has(techs[i])) return true;
      }
      return false;
    }

    function applyFilters() {
      var visibleCount = 0;
      var totalCount = cards.length;

      cards.forEach(function (card) {
        var wasHidden = card.classList.contains('is-hidden');
        var shouldShow = cardMatches(card);

        if (shouldShow) {
          if (wasHidden) {
            card.classList.remove('is-hidden');
            card.classList.remove('is-filtering-out');
            card.classList.add('is-filtering-in');
            setTimeout(function () { card.classList.remove('is-filtering-in'); }, 320);
          }
          visibleCount++;
        } else {
          if (!wasHidden) {
            card.classList.add('is-filtering-out');
            setTimeout(function () {
              if (!cardMatches(card)) card.classList.add('is-hidden');
              card.classList.remove('is-filtering-out');
            }, 220);
          } else {
            card.classList.add('is-hidden');
          }
        }
      });

      if (active.size === 0) {
        if (statusEl) {
          statusEl.hidden = true;
        }
        if (countEl) countEl.textContent = '';
        if (emptyEl) emptyEl.hidden = true;
      } else {
        if (statusEl) statusEl.hidden = false;
        if (countEl) {
          var labels = Array.from(active).map(function (t) {
            var pill = document.querySelector('.stack-pill[data-filter="' + t + '"]');
            return pill ? pill.textContent.trim() : t;
          });
          countEl.innerHTML = '';
          var strong = document.createElement('strong');
          strong.textContent = visibleCount + ' of ' + totalCount;
          countEl.appendChild(strong);
          countEl.appendChild(document.createTextNode(' projects '));
          var div = document.createElement('span');
          div.className = 'filter-status-divider';
          div.textContent = '·';
          countEl.appendChild(div);
          countEl.appendChild(document.createTextNode(' ' + labels.join(', ')));
        }
        if (emptyEl) emptyEl.hidden = visibleCount > 0;
      }
    }

    function togglePill(pill) {
      var key = pill.getAttribute('data-filter');
      if (!key) return;
      if (active.has(key)) {
        active.delete(key);
        pill.setAttribute('aria-pressed', 'false');
      } else {
        active.add(key);
        pill.setAttribute('aria-pressed', 'true');
      }
      applyFilters();
    }

    function clearAll() {
      active.clear();
      pills.forEach(function (p) { p.setAttribute('aria-pressed', 'false'); });
      applyFilters();
    }

    pills.forEach(function (pill) {
      pill.addEventListener('click', function () { togglePill(pill); });
    });

    clearBtns.forEach(function (b) {
      b.addEventListener('click', clearAll);
    });
  }

  function initPdfViewer() {
    var modal = document.querySelector('[data-pdf-modal]');
    var triggers = document.querySelectorAll('[data-pdf]');
    if (!modal || !triggers.length) return;

    var frame = modal.querySelector('[data-pdf-frame]');
    var titleEl = modal.querySelector('[data-pdf-modal-title]');
    var openLink = modal.querySelector('[data-pdf-open]');
    var closeEls = modal.querySelectorAll('[data-pdf-close]');
    var lastTrigger = null;

    function open(url, title) {
      if (frame) frame.src = url;
      if (openLink) openLink.href = url;
      if (titleEl && title) titleEl.textContent = title;
      modal.hidden = false;
      document.body.classList.add('modal-open');
    }

    function close() {
      modal.hidden = true;
      document.body.classList.remove('modal-open');
      // Stop rendering / free the embedded document
      if (frame) frame.src = 'about:blank';
      if (lastTrigger) lastTrigger.focus();
    }

    triggers.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var url = btn.getAttribute('data-pdf');
        // Mobile browsers (especially iOS Safari) can't render a PDF inside an
        // iframe — they show a broken/blank icon. Open it directly instead so
        // the device's native PDF viewer handles it.
        if (window.matchMedia('(max-width: 768px)').matches) {
          window.open(url, '_blank', 'noopener');
          return;
        }
        lastTrigger = btn;
        open(url, btn.getAttribute('data-pdf-title'));
      });
    });

    closeEls.forEach(function (el) {
      el.addEventListener('click', close);
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && !modal.hidden) close();
    });
  }

  function initYearTimeline() {
    var section = document.getElementById('projects');
    var railItems = Array.prototype.slice.call(document.querySelectorAll('[data-year-rail]'));
    var cards = Array.prototype.slice.call(document.querySelectorAll('.project-card[data-year]'));
    var chip = document.querySelector('[data-year-chip]');
    if (!section || !cards.length) return;

    var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var ticking = false;

    function visibleCards() {
      return cards.filter(function (c) {
        // skip cards hidden by the skill filter
        return !c.classList.contains('is-hidden') && c.offsetParent !== null;
      });
    }

    function activeYear() {
      var vis = visibleCards();
      if (!vis.length) return null;
      var refLine = window.innerHeight * 0.32;
      var current = vis[0];
      vis.forEach(function (c) {
        if (c.getBoundingClientRect().top <= refLine) current = c;
      });
      return current.getAttribute('data-year');
    }

    function sectionInView() {
      var r = section.getBoundingClientRect();
      return r.bottom > 0 && r.top < window.innerHeight;
    }

    function update() {
      if (!sectionInView()) {
        if (chip) chip.classList.remove('is-visible');
        return;
      }
      var year = activeYear();
      if (!year) return;

      railItems.forEach(function (it) {
        it.classList.toggle('is-active', it.getAttribute('data-year-rail') === year);
      });
      cards.forEach(function (c) {
        if (c.classList.contains('is-hidden')) return;
        c.classList.toggle('off-year', c.getAttribute('data-year') !== year);
      });
      if (chip) {
        chip.textContent = year;
        chip.classList.add('is-visible');
      }
    }

    function onScroll() {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(function () {
        update();
        ticking = false;
      });
    }

    // Clicking a year jumps to its first (visible) project
    railItems.forEach(function (it) {
      it.addEventListener('click', function () {
        var y = it.getAttribute('data-year-rail');
        var target = visibleCards().filter(function (c) {
          return c.getAttribute('data-year') === y;
        })[0];
        if (!target) return;
        var top = target.getBoundingClientRect().top + window.pageYOffset - 80;
        window.scrollTo({ top: top, behavior: reduceMotion ? 'auto' : 'smooth' });
      });
    });

    // Recompute after a skill filter changes the visible set (let the animation settle)
    document.addEventListener('click', function (e) {
      var t = e.target;
      if (t && t.closest && t.closest('.stack-pill, [data-filter-clear]')) {
        setTimeout(update, 360);
      }
    });

    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
    update();
  }

  function init() {
    initNav();
    initFilters();
    initPdfViewer();
    initYearTimeline();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
