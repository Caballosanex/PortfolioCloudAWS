var pdfFiles = {
  es: '/cv/CV_Alex_Sanchez_Blabia_ES.pdf?v=20261103',
  en: '/cv/CV_Alex_Sanchez_Blabia_EN.pdf?v=20261103',
  ca: '/cv/CV_Alex_Sanchez_Blabia_CA.pdf?v=20261103'
};
var currentLang = 'es';
var loader = document.getElementById('iframe-loader');
var downloadLink = document.getElementById('download-link');
var iframe = document.getElementById('cv-preview');

fetch('/cv/api/count', { method: 'POST' })
  .then(function(r) { return r.json(); })
  .then(function(d) { document.getElementById('counter').textContent = d.count; })
  .catch(function() { document.getElementById('counter').textContent = '-'; });

iframe.addEventListener('load', function() { loader.style.display = 'none'; });
iframe.src = pdfFiles[currentLang];

document.querySelectorAll('.lang-tab').forEach(function(btn) {
  btn.addEventListener('click', function() {
    currentLang = this.dataset.lang;
    downloadLink.href = pdfFiles[currentLang];
    loader.style.display = 'flex';
    iframe.src = pdfFiles[currentLang];
    document.querySelectorAll('.lang-tab').forEach(function(t) { t.classList.remove('active'); });
    this.classList.add('active');
  });
});
