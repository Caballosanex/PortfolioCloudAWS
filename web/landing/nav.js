(function () {
  'use strict';

  function init() {
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

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
