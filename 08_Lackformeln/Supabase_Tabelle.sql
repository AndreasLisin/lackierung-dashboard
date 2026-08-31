-- ============================================================
-- Lackformeln – Supabase-Tabellen + RLS
-- Projekt: einhaus-ruestfreigabe (tldkqifblxkdligypffr)
-- Einmal im Supabase SQL-Editor ausfuehren.
-- ============================================================

-- ---------- 1) Formeln (Master-Spiegel aus Excel) ----------
-- Wird vom Sync-Task (Sync_Lackformeln.ps1) bei jedem Lauf komplett
-- neu befuellt. Die Excel bleibt die fuehrende Quelle.
create table if not exists public.lackformeln (
  id             bigserial primary key,
  kunde          text not null,
  farbname       text not null,
  farbcode       text,
  system         text,                       -- z.B. "Hit 3", "Basislack"
  typ            text,                        -- Uni / Metallic / Perl / Effekt
  komponenten    jsonb not null default '[]', -- [{ "code":"MB 501","gramm":851.7,("gruppe":"Grundton") }]
  primer         text,
  klarlack       text,
  haerter        text,
  vorlage_nr     text,
  notiz          text,
  quelle_blatt   text,
  quelle_zeile   int,
  geprueft       boolean not null default false,
  aktualisiert_am timestamptz not null default now()
);

create index if not exists lackformeln_kunde_idx on public.lackformeln (kunde);
create index if not exists lackformeln_suche_idx on public.lackformeln
  using gin (to_tsvector('simple', coalesce(farbname,'') || ' ' || coalesce(farbcode,'')));

-- ---------- 2) Eingang (Neuanlagen aus dem Dashboard) ----------
-- Neue Formeln, die im Dashboard eingegeben werden.
--   status     : 'offen'    = aktive Dashboard-Neuanlage, wird bei jedem Sync
--                             zusaetzlich in die Anzeige (lackformeln) eingespielt
--                'erledigt' = in den Excel-Master uebernommen -> nicht mehr einspielen
--   exportiert : true, sobald in die Begleitdatei Dashboard_Neu.xlsx geschrieben
-- Der Excel-MASTER wird vom Sync NICHT beschrieben (nur gelesen) – die Neuanlagen
-- landen in der separaten Datei Dashboard_Neu.xlsx zum gefahrlosen Einpflegen.
create table if not exists public.lackformeln_eingang (
  id           bigserial primary key,
  kunde        text not null,
  farbname     text not null,
  system       text,
  komponenten  jsonb not null default '[]',
  primer       text,
  klarlack     text,
  haerter      text,
  notiz        text,
  erfasst_von  text,
  status       text not null default 'offen',
  exportiert   boolean not null default false,
  erstellt_am  timestamptz not null default now()
);

create index if not exists lackformeln_eingang_status_idx
  on public.lackformeln_eingang (status);

-- ---------- 3) Row Level Security ----------
-- Haertung 31.08.2026 (Sicherheits-Review, Manuel Einhaus): anon hatte hier
-- Lese- UND Schreibzugriff (using(true)/with check(true)) - zusammen mit dem
-- oeffentlich eingebetteten anon-Key waren die Lackformeln fuer jeden im
-- Internet les- und beschreibbar. Rotation des Keys allein haette nichts
-- gebracht, der neue Key haette wieder im HTML gelegen. Deshalb: keine
-- anon-Policies mehr. Zugriff laeuft kuenftig ausschliesslich ueber ein
-- Backend (service_role bzw. wincarat-api), nie direkt vom Client aus.
-- Dieses Supabase-Projekt ist ohnehin dauerhaft abgeschaltet (kein Restore,
-- Entscheidung Manuel 26.08.2026) - diese Datei ist Referenz/Historie.
alter table public.lackformeln          enable row level security;
alter table public.lackformeln_eingang  enable row level security;

drop policy if exists "lackformeln_select_anon" on public.lackformeln;
drop policy if exists "eingang_insert_anon" on public.lackformeln_eingang;
drop policy if exists "eingang_select_anon" on public.lackformeln_eingang;
-- Keine Ersatz-Policies fuer anon: ohne Policy verweigert RLS per Default
-- jeden Zugriff. Lesen/Schreiben ausschliesslich ueber service_role
-- (serverseitig, nie im Client-Code).
