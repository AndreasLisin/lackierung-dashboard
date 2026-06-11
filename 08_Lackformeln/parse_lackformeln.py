# -*- coding: utf-8 -*-
"""
Parser fuer Lackformeln.xlsx (EINHAUS Oberflaechenveredelung GmbH).

Liest die block-basierte Excel (1 Blatt = 1 Kunde) und erzeugt strukturierte
Lackformeln als JSON. Heuristisch: erkennt Farbname, Farbcode, System (Hit X),
Komponenten (Toenpaste-Code + Gramm), Primer/Klarlack/Haerter, Vorlage-Nr. und
Notizen. Jeder Datensatz bekommt ein Konfidenz-Flag "geprueft".

Aufruf:
    python parse_lackformeln.py "Pfad\\Lackformeln.xlsx"          -> JSON nach stdout
    python parse_lackformeln.py "Pfad\\Lackformeln.xlsx" --review  -> zusaetzlich Review_Lackformeln.xlsx

Wird vom Sync-Task (Sync_Lackformeln.ps1) aufgerufen.
"""
import sys
import os
import re
import json
import math

import pandas as pd

# Standard-Pfad zur Master-Excel (kann per Argument ueberschrieben werden)
DEFAULT_XLSX = r"C:\Users\lisina\einhaus-gmbh.de\Lackierung - Dokumente\4. Lackformeln\Lackformeln.xlsx"

# Blaetter, die keine sauberen Rezepte enthalten:
# - "Canyon Liste": reine Inhaltsliste
# - "VW City Wings 06_2022" / "(2)": Vergleichs-/Mess-Arbeitsblaetter (mehrere
#   Wertspalten, Datumswerte) – bei Bedarf hier entfernen, um sie wieder aufzunehmen.
SKIP_SHEETS = {"Canyon Liste", "VW City Wings 06_2022", "VW City Wings 06_2022 (2)"}

# Plausibler Gramm-Bereich: groessere Werte sind i.d.R. Datums-/ID-Artefakte
MAX_GRAMM = 100000

# Schluesselwoerter
RE_SYSTEM      = re.compile(r"^\s*hit\s*\d+\s*$", re.I)
RE_GROUP_LABEL = re.compile(r"^\s*(grundton|effekt|basislack|deckton|perl\.?|grundlack|decklack)\b", re.I)
RE_PRIMER      = re.compile(r"primer", re.I)
RE_KLARLACK    = re.compile(r"klarlack|klar(?!\w)", re.I)
RE_HAERTER     = re.compile(r"h(ae|ä|a)rter", re.I)
RE_VORLAGE     = re.compile(r"vorlage", re.I)

# Farbcode-Muster (im Farbnamen gesucht), z.B. LB9A, T5U, 7-956, 9-885, 1K0, 3T3, RAL 5010
RE_CODE_IN_NAME = re.compile(
    r"\b("
    r"RAL\s?\d{3,4}"          # RAL 5010
    r"|[A-Z0-9]{1,2}-\d{3,4}" # 7-956, 9-885
    r"|L?[A-Z]\d[A-Z0-9]"     # LB9A, T5U, B3Z
    r"|\d[A-Z]\d"             # 1K0, 3T3, 1G3
    r"|\d{3,4}"               # 3393, 9885
    r")\b"
)


def is_nan(v):
    if v is None:
        return True
    if isinstance(v, float) and math.isnan(v):
        return True
    if isinstance(v, str) and v.strip().lower() in ("", "nan"):
        return True
    return False


def to_amount(v):
    """Wandelt einen Wert in eine Gramm-Zahl, sonst None."""
    if is_nan(v):
        return None
    if isinstance(v, (int, float)):
        f = float(v)
        return None if math.isnan(f) else f
    s = str(v).strip().replace(" ", "")
    s = s.replace(".", "") if s.count(".") > 1 else s   # 1.234 (Tausender) selten
    s = s.replace(",", ".")
    try:
        return float(s)
    except ValueError:
        return None


def clean(v):
    return "" if is_nan(v) else str(v).strip()


def looks_like_code(s):
    """Kurzer Toenpaste-/Komponenten-Code, z.B. '502', 'MB 501', 'LL4U', '299'."""
    s = s.strip()
    if not s or len(s) > 12:
        return False
    if RE_SYSTEM.match(s) or RE_GROUP_LABEL.match(s):
        return False
    # erlaubt: Buchstaben/Ziffern, ein Leerzeichen, Punkt, Bindestrich
    return bool(re.match(r"^[A-Za-z0-9][A-Za-z0-9 .\-]{0,11}$", s))


def find_code(name):
    m = RE_CODE_IN_NAME.search(name or "")
    return m.group(1) if m else None


def guess_typ(text):
    t = (text or "").lower()
    if "perl" in t:
        return "Perl"
    if "effekt" in t:
        return "Effekt"
    if "metallic" in t or "metalic" in t:
        return "Metallic"
    return "Uni"


def as_code(a):
    """Gibt den Code-String zurueck, wenn die Zelle ein Komponenten-Code sein kann."""
    if is_nan(a):
        return None
    if isinstance(a, (int, float)):
        # ganzzahliger Toenpaste-Code (z.B. 552, 502, 299) – keine Kommazahl.
        # Mind. 3-stellig: 1-/2-stellige Werte sind fast immer Rausch-/Zaehlzeilen.
        f = float(a)
        if f == int(f) and 100 <= f <= 99999:
            return str(int(f))
        return None
    code = clean(a)
    return code if looks_like_code(code) else None


def extract_pairs(row):
    """Liefert Liste von (code, gramm, spalte) fuer benachbarte Code+Zahl-Paare."""
    pairs = []
    vals = list(row)
    j = 0
    while j < len(vals) - 1:
        code = as_code(vals[j])
        if code:
            amt = to_amount(vals[j + 1])
            if amt is not None and 0 < amt <= MAX_GRAMM:
                pairs.append((code, amt, j))
                j += 2
                continue
        j += 1
    return pairs


def text_cells(row):
    """Nicht-leere Textzellen (keine reinen Zahlen) mit Spaltenindex."""
    out = []
    for j, v in enumerate(row):
        if is_nan(v):
            continue
        if isinstance(v, (int, float)):
            continue
        s = clean(v)
        if s and not re.match(r"^[\d.,]+$", s):
            out.append((j, s))
    return out


def parse_sheet(df, sheet):
    """Zerlegt ein Blatt in Formel-Bloecke."""
    rows = [list(r) for r in df.itertuples(index=False, name=None)]
    blocks = []
    cur = None          # aktueller Block
    empty_run = 0
    carry = []          # Titel eines vorausgehenden titellosen Blocks (Titel | Leerzeile | Komponenten)

    def flush():
        nonlocal cur, carry
        if cur and cur["komponenten"]:
            blocks.append(cur)
        elif cur and cur["_titles"]:
            # Block ohne Komponenten, aber mit Titel -> Titel an naechsten Block weiterreichen
            carry = cur["_titles"]
        cur = None

    def start_block(row_idx):
        nonlocal cur, carry
        cur = new_block(sheet, row_idx)
        if carry:
            cur["_titles"].extend(carry)
            carry = []

    for i, row in enumerate(rows):
        pairs = extract_pairs(row)
        texts = text_cells(row)
        is_empty = not pairs and not texts

        if is_empty:
            empty_run += 1
            if empty_run >= 1:
                flush()
            continue
        empty_run = 0

        if pairs:
            if cur is None:
                start_block(i)
            # aktuelles Gruppenlabel je Spalte beruecksichtigen
            consumed = set()
            for (code, amt, col) in pairs:
                grp = group_for_col(cur, col)
                cur["komponenten"].append({"code": code, "gramm": amt,
                                           "gruppe": grp, "_col": col})
                consumed.add(col)
                consumed.add(col + 1)
            # nur Resttext (nicht von Paaren belegt) als Attribut/Notiz pruefen
            for (col, s) in texts:
                if col not in consumed:
                    classify_text(cur, s, col)
        else:
            # reine Textzeile: Label / Titel / Attribut.
            # Neuer Titel + bestehende Komponenten => neue Formel beginnt.
            has_title = any(text_role(s) == "title" for _, s in texts)
            if cur and cur["komponenten"] and has_title:
                flush()
            if cur is None:
                start_block(i)
            for (col, s) in texts:
                classify_text(cur, s, col)
    flush()
    return [finalize(b) for b in blocks]


def new_block(sheet, row):
    return {
        "kunde": sheet,
        "farbname": "",
        "farbcode": None,
        "system": None,
        "typ": None,
        "komponenten": [],
        "primer": None,
        "klarlack": None,
        "haerter": None,
        "vorlage_nr": None,
        "notiz": None,
        "quelle_blatt": sheet,
        "quelle_zeile": int(row) + 1,
        "_labels": [],          # (col, label)
        "_titles": [],
    }


def group_for_col(block, col):
    """Naechstliegendes Gruppenlabel links/gleich der Spalte."""
    best = None
    best_d = 99
    for (lcol, label) in block["_labels"]:
        d = abs(col - lcol)
        if d < best_d:
            best_d = d
            best = label
    return best


def text_role(s):
    """Reine Klassifikation einer Textzelle (mutiert nichts)."""
    if RE_SYSTEM.match(s):
        return "system"
    if RE_GROUP_LABEL.match(s):
        return "label"
    if RE_VORLAGE.search(s):
        return "vorlage"
    if RE_PRIMER.search(s):
        return "primer"
    if RE_KLARLACK.search(s):
        return "klarlack"
    if RE_HAERTER.search(s):
        return "haerter"
    return "title"


def classify_text(block, s, col):
    """Ordnet eine Textzelle einem Block zu."""
    if block is None:
        return
    s = s.strip()
    role = text_role(s)
    if role == "system":
        block["system"] = s
    elif role == "label":
        block["_labels"].append((col, s.rstrip(".")))
        if re.match(r"^\s*basislack", s, re.I) and not block["system"]:
            block["system"] = s
    elif role == "vorlage":
        block["vorlage_nr"] = s
    elif role == "primer":
        block["primer"] = s
    elif role == "klarlack":
        block["klarlack"] = s
    elif role == "haerter":
        block["haerter"] = s
    else:
        block["_titles"].append(s)


def finalize(b):
    titles = b.pop("_titles", [])
    b.pop("_labels", None)
    # Farbname = laengster/erster sinnvoller Titel
    name = ""
    for t in titles:
        if len(t) > len(name):
            name = t
    if not name and titles:
        name = titles[0]
    b["farbname"] = name or "(ohne Titel)"
    if len(titles) > 1:
        extra = " | ".join(t for t in titles if t != name)
        b["notiz"] = (b.get("notiz") + " | " + extra) if b.get("notiz") else extra
    b["farbcode"] = find_code(b["farbname"])
    b["typ"] = guess_typ(" ".join(titles) + " " + (b.get("system") or ""))
    # _col aus Komponenten entfernen, Gruppe nur behalten wenn >1 Gruppe
    groups = {k.get("gruppe") for k in b["komponenten"]}
    multi = len([g for g in groups if g]) > 1
    for k in b["komponenten"]:
        k.pop("_col", None)
        if not multi:
            k.pop("gruppe", None)
        elif k.get("gruppe") is None:
            k["gruppe"] = ""
    # Konfidenz
    b["geprueft"] = bool(
        b["farbname"] != "(ohne Titel)"
        and len(b["komponenten"]) >= 2
        and all(k["gramm"] and k["gramm"] > 0 for k in b["komponenten"])
    )
    return b


def parse_workbook(path):
    xl = pd.ExcelFile(path)
    out = []
    for sheet in xl.sheet_names:
        if sheet in SKIP_SHEETS:
            continue
        df = pd.read_excel(path, sheet_name=sheet, header=None)
        if df.empty:
            continue
        out.extend(parse_sheet(df, sheet))
    return out


def write_review(records, xlsx_path):
    rows = []
    for r in records:
        komp = "; ".join(
            f"{k['code']}={k['gramm']:g}" + (f" [{k['gruppe']}]" if k.get("gruppe") else "")
            for k in r["komponenten"]
        )
        rows.append({
            "geprueft": "ja" if r["geprueft"] else "PRUEFEN",
            "kunde": r["kunde"],
            "farbname": r["farbname"],
            "farbcode": r["farbcode"] or "",
            "system": r["system"] or "",
            "typ": r["typ"],
            "komponenten": komp,
            "primer": r["primer"] or "",
            "klarlack": r["klarlack"] or "",
            "haerter": r["haerter"] or "",
            "vorlage_nr": r["vorlage_nr"] or "",
            "notiz": r["notiz"] or "",
            "quelle": f"{r['quelle_blatt']}!Z{r['quelle_zeile']}",
        })
    df = pd.DataFrame(rows)
    df.to_excel(xlsx_path, index=False)


def get_flag_value(flags_raw, name):
    """Liest --name=wert oder --name wert."""
    for i, a in enumerate(flags_raw):
        if a == name and i + 1 < len(flags_raw):
            return flags_raw[i + 1]
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return None


def main():
    raw = sys.argv[1:]
    args = [a for a in raw if not a.startswith("--")]
    flags = [a for a in raw if a.startswith("--")]
    path = args[0] if args else DEFAULT_XLSX
    records = parse_workbook(path)

    if "--review" in flags:
        review_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   "Review_Lackformeln.xlsx")
        write_review(records, review_path)
        ok = sum(1 for r in records if r["geprueft"])
        sys.stderr.write(
            f"{len(records)} Formeln geparst, {ok} geprueft, "
            f"{len(records)-ok} zu pruefen.\nReview: {review_path}\n"
        )

    out_path = get_flag_value(raw, "--out")
    text = json.dumps(records, ensure_ascii=False, indent=2)
    if out_path:
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(text)
        sys.stderr.write(f"{len(records)} Formeln -> {out_path}\n")
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
