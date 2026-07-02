/* Wenn dieses Tool ueber die Einhaus Prozesslandschaft geoeffnet wurde, zeigt der
   "Zurueck"-Knopf zur Prozesslandschaft statt zum Dashboard Lackierung.
   Wirkt NUR, wenn das Merkzeichen "pl-back-to" gesetzt ist (von der Prozesslandschaft
   beim Anklicken einer Kachel). Direkt aufgerufene/verlesezeichnete Tools (z.B. Tablets
   in der Werkstatt) bleiben unveraendert. */
(function () {
  try {
    var raw = localStorage.getItem("pl-back-to");
    if (!raw) return;
    var data = JSON.parse(raw);
    if (!data || !data.url) return;
    var maxAgeMs = 6 * 60 * 60 * 1000; // 6 Stunden gueltig
    if (!data.ts || Date.now() - data.ts > maxAgeMs) {
      localStorage.removeItem("pl-back-to");
      return;
    }
    document.addEventListener("DOMContentLoaded", function () {
      var link = document.querySelector('a.btn-back[href="../index.html"]');
      if (link) {
        link.setAttribute("href", data.url);
        link.textContent = "← " + (data.label || "Prozesslandschaft");
      }
    });
    localStorage.removeItem("pl-back-to");
  } catch (e) {
    /* kein Effekt bei Fehlern - Standardverhalten bleibt erhalten */
  }
})();
