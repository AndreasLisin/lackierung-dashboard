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
alter table public.lackformeln          enable row level security;
alter table public.lackformeln_eingang  enable row level security;

-- anon darf Formeln lesen
drop policy if exists "lackformeln_select_anon" on public.lackformeln;
create policy "lackformeln_select_anon"
  on public.lackformeln for select
  to anon using (true);

-- anon darf Neuanlagen anlegen und sehen (Schreiben/Aendern der Master-
-- Tabelle sowie Statuswechsel laufen ueber service_role und umgehen RLS)
drop policy if exists "eingang_insert_anon" on public.lackformeln_eingang;
create policy "eingang_insert_anon"
  on public.lackformeln_eingang for insert
  to anon with check (true);

drop policy if exists "eingang_select_anon" on public.lackformeln_eingang;
create policy "eingang_select_anon"
  on public.lackformeln_eingang for select
  to anon using (true);
