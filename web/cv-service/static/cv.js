var isMobile = window.matchMedia('(pointer: coarse)').matches;
var loader = document.getElementById('iframe-loader');
var downloadLink = document.getElementById('download-link');

if (typeof pdfjsLib !== 'undefined') {
  pdfjsLib.GlobalWorkerOptions.workerSrc = '/cv/static/pdf.worker.min.js';
}

function renderPDF(lang) {
  var container = document.getElementById('pdf-canvas-container');
  loader.style.display = 'flex';
  container.innerHTML = '';

  pdfjsLib.getDocument('/cv/preview/' + lang).promise.then(function(pdf) {
    var chain = Promise.resolve();
    for (var i = 1; i <= pdf.numPages; i++) {
      (function(pageNum) {
        chain = chain.then(function() {
          return pdf.getPage(pageNum).then(function(page) {
            var dpr = window.devicePixelRatio || 1;
            var scale = (container.clientWidth - 24) / page.getViewport({ scale: 1 }).width;
            var viewport = page.getViewport({ scale: scale * dpr });
            var canvas = document.createElement('canvas');
            canvas.width = viewport.width;
            canvas.height = viewport.height;
            canvas.style.width = (viewport.width / dpr) + 'px';
            canvas.style.height = (viewport.height / dpr) + 'px';
            container.appendChild(canvas);
            return page.render({ canvasContext: canvas.getContext('2d'), viewport: viewport }).promise;
          });
        });
      })(i);
    }
    return chain;
  }).then(function() {
    loader.style.display = 'none';
  }).catch(function() {
    loader.style.display = 'none';
  });
}

if (isMobile) {
  document.querySelector('.preview-container').style.display = 'none';
  document.getElementById('preview-mobile').style.display = 'block';
  renderPDF('es');
} else {
  var iframe = document.getElementById('cv-preview');
  iframe.addEventListener('load', function() {
    loader.style.display = 'none';
  });
  iframe.src = '/cv/preview/es';
}

document.querySelectorAll('.lang-tab').forEach(function(btn) {
  btn.addEventListener('click', function() {
    var lang = this.dataset.lang;
    downloadLink.href = '/cv/download/' + lang;

    if (isMobile) {
      renderPDF(lang);
    } else {
      var iframe = document.getElementById('cv-preview');
      loader.style.display = 'flex';
      iframe.src = '/cv/preview/' + lang;
    }

    document.querySelectorAll('.lang-tab').forEach(function(t) { t.classList.remove('active'); });
    this.classList.add('active');
  });
});
