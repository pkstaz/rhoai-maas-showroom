(function () {
  var STORAGE_KEY = 'lab-theme';
  var DARK_CLASS = 'pf-v5-theme-dark';

  function isDark() {
    return document.documentElement.classList.contains(DARK_CLASS);
  }

  function apply(theme) {
    var dark = theme !== 'light';
    document.documentElement.classList.toggle(DARK_CLASS, dark);
    try {
      localStorage.setItem(STORAGE_KEY, dark ? 'dark' : 'light');
    } catch (e) {}
    var btn = document.getElementById('theme-toggle');
    if (btn) {
      var label = btn.querySelector('.theme-toggle-label');
      if (label) label.textContent = dark ? 'Light' : 'Dark';
      btn.setAttribute('aria-pressed', dark ? 'true' : 'false');
      btn.title = dark ? 'Cambiar a tema claro' : 'Cambiar a tema oscuro';
    }
  }

  function preferred() {
    try {
      var saved = localStorage.getItem(STORAGE_KEY);
      if (saved === 'light' || saved === 'dark') return saved;
    } catch (e) {}
    return 'dark';
  }

  apply(preferred());

  document.addEventListener('DOMContentLoaded', function () {
    apply(isDark() ? 'dark' : 'light');
    var btn = document.getElementById('theme-toggle');
    if (!btn) return;
    btn.addEventListener('click', function () {
      apply(isDark() ? 'light' : 'dark');
    });
  });
})();
