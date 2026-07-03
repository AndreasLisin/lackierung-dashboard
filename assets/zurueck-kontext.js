/* Wenn dieses Tool ueber die Einhaus Prozesslandschaft geoeffnet wurde (erkennbar am
   URL-Parameter "plZurueck"), zeigt der "Zurueck"-Knopf zur Prozesslandschaft statt
   zum Dashboard Lackierung. Direkt aufgerufene/verlesezeichnete Tools (z.B. Tablets in
   der Werkstatt) haben diesen Parameter nicht und bleiben unveraendert. */
(function () {
  try {
    var params = new URLSearchParams(window.location.search);
    var backUrl = params.get("plZurueck");
    if (!backUrl) return;
    document.addEventListener("DOMContentLoaded", function () {
      var link = document.querySelector('a.btn-back[href="../index.html"]');
      if (link) {
        link.setAttribute("href", backUrl);
        link.textContent = "← Prozesslandschaft";
      }
    });
  } catch (e) {
    /* kein Effekt bei Fehlern - Standardverhalten bleibt erhalten */
  }
})();
