/* Wenn dieses Tool ueber die Einhaus Prozesslandschaft geoeffnet wurde (erkennbar am
   URL-Parameter "plZurueck"), zeigt der "Zurueck"-Knopf zur Prozesslandschaft statt
   zum Dashboard Lackierung. Direkt aufgerufene/verlesezeichnete Tools (z.B. Tablets in
   der Werkstatt) haben diesen Parameter nicht und bleiben unveraendert. */
// Sicherheits-Review 31.08.2026 (Manuel Einhaus): "plZurueck" kam vorher ungeprueft
// als href rein - ein Link mit ?plZurueck=javascript:... haette bei Klick auf den
// "Zurueck"-Knopf beliebigen Code im Origin der Seite ausgefuehrt (auf Seiten mit
// Supabase-Login waere das Sitzungstoken aus dem localStorage abgreifbar gewesen).
// Deshalb: nur echte http(s)-URLs zu einem erlaubten Host werden uebernommen, alles
// andere (javascript:, data:, fremde Domains ...) wird ignoriert - Standardverhalten
// (Link zeigt weiterhin auf ../index.html) bleibt dann einfach erhalten.
var ERLAUBTE_HOSTS = ["andreaslisin.github.io"];

function istErlaubtesZurueckZiel(url) {
  try {
    var u = new URL(url, window.location.href);
    return (u.protocol === "http:" || u.protocol === "https:") &&
           ERLAUBTE_HOSTS.indexOf(u.hostname) !== -1;
  } catch (e) {
    return false;
  }
}

(function () {
  try {
    var params = new URLSearchParams(window.location.search);
    var backUrl = params.get("plZurueck");
    if (!backUrl || !istErlaubtesZurueckZiel(backUrl)) return;
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
