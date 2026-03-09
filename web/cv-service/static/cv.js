var iframe = document.getElementById('cv-preview');
var loader = document.getElementById('iframe-loader');

iframe.addEventListener('load', function() {
  loader.style.display = 'none';
});

// Set src after attaching listener so the load event is always caught
iframe.src = '/cv/preview/es';

document.querySelectorAll('.lang-tab').forEach(function(btn) {
  btn.addEventListener('click', function() {
    var lang = this.dataset.lang;
    loader.style.display = 'flex';
    iframe.src = '/cv/preview/' + lang;
    document.getElementById('download-link').href = '/cv/download/' + lang;
    document.querySelectorAll('.lang-tab').forEach(function(t) { t.classList.remove('active'); });
    this.classList.add('active');
  });
});
