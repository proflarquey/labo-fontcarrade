-- Inventaire des laboratoires de SVT et de physique-chimie · Collège Fontcarrade — Supabase / PostgreSQL
-- Version 2. Exécuter dans SQL Editor sur un projet Supabase réservé au laboratoire.
-- Le script peut être relancé sur une base créée avec la version 1 : les données sont conservées.
BEGIN;

-- ───────────────────────── Tables ─────────────────────────
CREATE TABLE IF NOT EXISTS public.labo_membres (
  email text PRIMARY KEY CHECK (email = lower(btrim(email))),
  nom text NOT NULL,
  actif boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.labo_articles (
  id uuid PRIMARY KEY,
  fiche jsonb NOT NULL,
  stock numeric(13,3) NOT NULL DEFAULT 0,
  emprunte numeric(13,3) NOT NULL DEFAULT 0,
  version integer NOT NULL DEFAULT 1,
  maj timestamptz NOT NULL DEFAULT now(),
  -- Dernier garde-fou : aucune requête ne peut laisser un stock négatif.
  CONSTRAINT labo_stock_coherent CHECK (stock >= 0 AND emprunte BETWEEN 0 AND stock)
);
CREATE UNIQUE INDEX IF NOT EXISTS labo_article_reference
  ON public.labo_articles (lower(btrim(fiche->>'supplier')), lower(btrim(fiche->>'ref')))
  WHERE coalesce(btrim(fiche->>'ref'), '') <> '';

CREATE TABLE IF NOT EXISTS public.labo_receptions (
  id uuid PRIMARY KEY,
  fournisseur text NOT NULL,
  numero text NOT NULL DEFAULT '',
  jour date NOT NULL,
  photos jsonb NOT NULL DEFAULT '[]',
  empreinte text NOT NULL DEFAULT '',
  auteur text NOT NULL,
  horodatage timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.labo_receptions ADD COLUMN IF NOT EXISTS auteur_email text NOT NULL DEFAULT '';
CREATE UNIQUE INDEX IF NOT EXISTS labo_reception_numero
  ON public.labo_receptions (lower(btrim(fournisseur)), lower(btrim(numero)))
  WHERE numero <> '';
CREATE UNIQUE INDEX IF NOT EXISTS labo_reception_photo
  ON public.labo_receptions (empreinte) WHERE empreinte <> '';

CREATE TABLE IF NOT EXISTS public.labo_mouvements (
  id uuid PRIMARY KEY,
  article_id uuid NOT NULL REFERENCES public.labo_articles(id),
  reception_id uuid REFERENCES public.labo_receptions(id),
  action text NOT NULL CHECK (action IN ('in','use','empty','out','loan','return')),
  quantite numeric(13,3) NOT NULL CHECK (quantite > 0),
  libelle text NOT NULL,
  unite text NOT NULL,
  motif text NOT NULL DEFAULT '',
  auteur text NOT NULL,
  horodatage timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.labo_mouvements ADD COLUMN IF NOT EXISTS auteur_email text NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS labo_mouvements_date ON public.labo_mouvements (horodatage DESC, id DESC);
CREATE INDEX IF NOT EXISTS labo_mouvements_article ON public.labo_mouvements (article_id);

-- Requêtes déjà traitées : un envoi répété (double appui, réseau coupé puis rétabli)
-- renvoie le premier résultat au lieu de créer un doublon.
CREATE TABLE IF NOT EXISTS public.labo_requetes (
  id uuid PRIMARY KEY,
  nature text NOT NULL,
  resultat jsonb NOT NULL,
  auteur text NOT NULL,
  horodatage timestamptz NOT NULL DEFAULT now()
);

-- Bons de commande (SVT et physique-chimie), numérotés par année : CMD-2026-001…
CREATE TABLE IF NOT EXISTS public.labo_commandes (
  id uuid PRIMARY KEY,
  numero text NOT NULL UNIQUE,
  annee integer NOT NULL,
  rang integer NOT NULL,
  fournisseur text NOT NULL,
  discipline text NOT NULL DEFAULT 'commun' CHECK (discipline IN ('svt','pc','commun')),
  lignes jsonb NOT NULL,
  total_ht numeric(14,2) NOT NULL,
  total_ttc numeric(14,2) NOT NULL,
  note text NOT NULL DEFAULT '',
  auteur text NOT NULL,
  auteur_email text NOT NULL DEFAULT '',
  horodatage timestamptz NOT NULL DEFAULT now(),
  UNIQUE (annee, rang)
);

-- Paramètres communs : coordonnées de l'établissement et logo des documents.
CREATE TABLE IF NOT EXISTS public.labo_parametres (
  id integer PRIMARY KEY CHECK (id = 1),
  valeurs jsonb NOT NULL DEFAULT '{}'
);
INSERT INTO public.labo_parametres(id) VALUES (1) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public.labo_sync (
  id integer PRIMARY KEY CHECK (id = 1),
  revision bigint NOT NULL DEFAULT 0
);
INSERT INTO public.labo_sync(id) VALUES (1) ON CONFLICT DO NOTHING;

ALTER TABLE public.labo_membres ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.labo_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.labo_mouvements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.labo_receptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.labo_requetes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.labo_sync ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.labo_commandes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.labo_parametres ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.labo_membres, public.labo_articles, public.labo_mouvements,
  public.labo_receptions, public.labo_requetes, public.labo_commandes, public.labo_parametres,
  public.labo_sync FROM anon, authenticated;
GRANT SELECT ON public.labo_sync TO authenticated;

-- ───────────────────────── Identité ─────────────────────────
CREATE OR REPLACE FUNCTION public.labo_est_membre()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.labo_membres
    WHERE email = lower(auth.jwt()->>'email') AND actif
  );
$$;

DROP POLICY IF EXISTS labo_sync_lecture ON public.labo_sync;
CREATE POLICY labo_sync_lecture ON public.labo_sync FOR SELECT TO authenticated
  USING ((SELECT public.labo_est_membre()));
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'labo_sync') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.labo_sync;
  END IF;
END;
$$;

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES ('labo-pieces', 'labo-pieces', false, 15000000, ARRAY['image/jpeg','application/pdf'])
ON CONFLICT (id) DO NOTHING;
DROP POLICY IF EXISTS labo_pieces_lecture ON storage.objects;
DROP POLICY IF EXISTS labo_pieces_ajout ON storage.objects;
CREATE POLICY labo_pieces_lecture ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'labo-pieces' AND (SELECT public.labo_est_membre()));
CREATE POLICY labo_pieces_ajout ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'labo-pieces' AND (SELECT public.labo_est_membre())
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
    AND storage.extension(name) IN ('jpg','pdf'));

CREATE OR REPLACE FUNCTION public.labo_identite()
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE personne text;
BEGIN
  SELECT nom INTO personne FROM public.labo_membres
  WHERE email = lower(auth.jwt()->>'email') AND actif AND auth.uid() IS NOT NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ce compte ne figure pas parmi les membres autorisés.'; END IF;
  RETURN personne;
END;
$$;

-- ───────────────────────── Lecture ─────────────────────────
CREATE OR REPLACE FUNCTION public.labo_etat()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE personne text := public.labo_identite();
BEGIN
  RETURN jsonb_build_object('actor', personne,
    'revision', (SELECT revision FROM public.labo_sync WHERE id = 1),
    'items', coalesce((SELECT jsonb_agg(fiche || jsonb_build_object(
      'id', id, 'stock', stock, 'borrowed', emprunte, 'version', version, 'updated', maj)
      ORDER BY fiche->>'name') FROM public.labo_articles), '[]'::jsonb),
    'receipts', coalesce((SELECT jsonb_agg(to_jsonb(bl) - 'auteur_email' ORDER BY horodatage DESC)
      FROM (SELECT * FROM public.labo_receptions ORDER BY horodatage DESC LIMIT 50) bl), '[]'::jsonb),
    'orders', coalesce((SELECT jsonb_agg(to_jsonb(c) - 'auteur_email' ORDER BY horodatage DESC)
      FROM (SELECT * FROM public.labo_commandes ORDER BY horodatage DESC LIMIT 60) c), '[]'::jsonb),
    'settings', (SELECT valeurs FROM public.labo_parametres WHERE id = 1)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.labo_journal(p_avant timestamptz DEFAULT NULL, p_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.labo_identite();
  RETURN coalesce((SELECT jsonb_agg(to_jsonb(m) - 'auteur_email' ORDER BY horodatage DESC, id DESC)
    FROM (SELECT * FROM public.labo_mouvements
      WHERE p_avant IS NULL OR (horodatage, id) < (p_avant, p_id)
      ORDER BY horodatage DESC, id DESC LIMIT 40) m), '[]'::jsonb);
END;
$$;

-- ───────────────────────── Contrôle des fiches ─────────────────────────
-- Comparaison d'identifiants : casse, espaces et séparateurs ignorés (« 10 % m/m » = « 10% M/M »).
-- La virgule décimale devient un point et reste significative : « 1,5 % » ≠ « 15 % ».
CREATE OR REPLACE FUNCTION public.labo_ident(t text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT lower(regexp_replace(replace(coalesce(t, ''), ',', '.'), '[[:space:];:_/()\-]+', '', 'g'));
$$;

-- Champs dont la modification remet en cause la vérification FDS.
CREATE OR REPLACE FUNCTION public.labo_securite_identique(a jsonb, b jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT bool_and((a->k) IS NOT DISTINCT FROM (b->k))
  FROM unnest(ARRAY['type','supplier','ref','spec','fdsSupplier','fdsRef','fdsSpec','fdsDate','fdsVersion',
    'fds','fdsLink','cas','clp','ghs','signal','hazards','storage','incompatible','family','location',
    'placeChecked']) AS k;
$$;

CREATE OR REPLACE FUNCTION public.labo_verifier_fiche(f jsonb)
RETURNS void LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF jsonb_typeof(f) IS DISTINCT FROM 'object' OR length(f::text) > 30000
    OR jsonb_typeof(f->'ghs') IS DISTINCT FROM 'array'
    OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(f->'ghs') AS p(code) WHERE code !~ '^SGH0[1-9]$')
    OR coalesce(length(btrim(f->>'name')), 0) NOT BETWEEN 1 AND 250
    OR coalesce(f->>'unit','') NOT IN ('pièce','boîte','flacon','lot','mL','L','g','kg','m')
    OR coalesce(f->>'type','') NOT IN ('equipment','consumable','chemical','review')
    OR coalesce((f->>'threshold')::numeric,0) NOT BETWEEN 0 AND 1000000
    OR coalesce(f->>'signal','unknown') NOT IN ('unknown','danger','warning','none')
    OR coalesce(f->>'clp','unknown') NOT IN ('unknown','confirmed','none')
    OR coalesce(f->>'discipline','commun') NOT IN ('svt','pc','commun')
    OR coalesce(f->>'priceHT','') !~ '^(\d{1,6}(\.\d{1,4})?)?$'
    OR coalesce(f->>'vat','20') NOT IN ('0','2.1','5.5','10','20')
    -- Pièces jointes : uniquement des fichiers du stockage privé du projet.
    OR coalesce(f->>'photo','') !~ '^([0-9a-f-]{36}/[0-9a-f-]{36}\.jpg)?$'
    OR coalesce(f->>'fds','') !~ '^([0-9a-f-]{36}/[0-9a-f-]{36}\.pdf)?$'
    OR coalesce(f->>'fdsLink','') !~ '^(https://\S+)?$' THEN
    RAISE EXCEPTION 'Fiche article incomplète ou quantité invalide.';
  END IF;
  IF coalesce((f->>'verified')::boolean,false) THEN
    IF f->>'type' <> 'chemical' THEN
      RAISE EXCEPTION 'La vérification FDS concerne les produits chimiques.';
    END IF;
    -- Lien avec la FDS exacte : même fournisseur, même référence, même concentration.
    IF coalesce(f->>'fds','') = '' AND coalesce(f->>'fdsLink','') = '' THEN
      RAISE EXCEPTION 'Joindre la FDS du fournisseur (PDF ou lien) avant de confirmer la vérification.'; END IF;
    IF public.labo_ident(f->>'supplier') = '' OR public.labo_ident(f->>'supplier') <> public.labo_ident(f->>'fdsSupplier') THEN
      RAISE EXCEPTION 'Le fournisseur indiqué sur la FDS doit être celui de l’article.'; END IF;
    IF public.labo_ident(f->>'ref') <> '' AND public.labo_ident(f->>'ref') <> public.labo_ident(f->>'fdsRef') THEN
      RAISE EXCEPTION 'La référence indiquée sur la FDS doit être celle de l’article.'; END IF;
    IF public.labo_ident(f->>'spec') = '' OR public.labo_ident(f->>'spec') <> public.labo_ident(f->>'fdsSpec') THEN
      RAISE EXCEPTION 'La concentration indiquée sur la FDS doit être celle de l’article.'; END IF;
    IF coalesce(f->>'fdsDate','') !~ '^\d{4}-\d{2}-\d{2}$' THEN
      RAISE EXCEPTION 'Indiquer la date de révision de la FDS.'; END IF;
    IF f->>'clp' NOT IN ('confirmed','none') OR f->>'signal' NOT IN ('danger','warning','none')
      OR (f->>'clp' = 'confirmed' AND (jsonb_array_length(f->'ghs') = 0 OR coalesce(btrim(f->>'hazards'),'') = '')) THEN
      RAISE EXCEPTION 'Relever l’étiquetage de la rubrique 2.2 : pictogrammes, mention d’avertissement et mentions de danger.'; END IF;
    IF coalesce(btrim(f->>'storage'),'') = '' OR coalesce(btrim(f->>'incompatible'),'') = '' THEN
      RAISE EXCEPTION 'Relever les rubriques 7.2 (stockage) et 10.5 (incompatibilités).'; END IF;
    IF coalesce(btrim(f->>'location'),'') = '' OR coalesce(f->>'family','unknown') = 'unknown'
      OR NOT coalesce((f->>'placeChecked')::boolean,false) THEN
      RAISE EXCEPTION 'Indiquer et constater sur place le compartiment réel et la famille de rangement.'; END IF;
  END IF;
END;
$$;

-- ───────────────────────── Mouvements ─────────────────────────
DROP FUNCTION IF EXISTS public.labo_appliquer_mouvement(uuid,uuid,text,numeric,text,text,uuid);
DROP FUNCTION IF EXISTS public.labo_bouger(jsonb);
DROP FUNCTION IF EXISTS public.labo_receptionner(jsonb);

CREATE OR REPLACE FUNCTION public.labo_appliquer_mouvement(
  p_id uuid, p_article uuid, p_type text, p_qte numeric, p_note text, p_auteur text, p_email text, p_bl uuid
) RETURNS jsonb LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE a public.labo_articles%ROWTYPE;
DECLARE m public.labo_mouvements%ROWTYPE;
DECLARE q numeric := p_qte;
DECLARE s numeric;
DECLARE e numeric;
BEGIN
  IF p_id IS NULL OR p_article IS NULL THEN RAISE EXCEPTION 'Mouvement incomplet.'; END IF;
  -- Verrou de ligne : deux mouvements sur le même article passent l’un après l’autre.
  SELECT * INTO a FROM public.labo_articles WHERE id = p_article FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Article introuvable.'; END IF;
  -- Mouvement déjà enregistré (nouvel envoi du même identifiant) : aucun effet, même résultat.
  SELECT * INTO m FROM public.labo_mouvements WHERE id = p_id;
  IF FOUND THEN
    IF m.article_id <> p_article THEN RAISE EXCEPTION 'Identifiant de mouvement déjà utilisé.'; END IF;
    RETURN jsonb_build_object('id', m.id, 'article', m.article_id, 'action', m.action, 'quantite', m.quantite,
      'unite', m.unite, 'libelle', m.libelle, 'auteur', m.auteur, 'horodatage', m.horodatage,
      'stock', a.stock, 'emprunte', a.emprunte, 'disponible', a.stock - a.emprunte, 'duplicate', true);
  END IF;
  IF p_type NOT IN ('in','use','empty','out','loan','return')
    OR q IS NULL OR q <= 0 OR q > 1000000 OR q <> round(q, 3) THEN
    RAISE EXCEPTION 'Quantité ou mouvement invalide.';
  END IF;
  IF a.fiche->>'unit' IN ('pièce','boîte','flacon','lot') AND q <> trunc(q) THEN
    RAISE EXCEPTION 'Saisir un nombre entier pour cette unité.';
  END IF;
  IF p_type IN ('use','empty','out','loan') AND q > a.stock - a.emprunte THEN
    RAISE EXCEPTION 'Stock disponible insuffisant : il reste % %. Un collègue a peut-être retiré ce produit entre-temps.',
      trim(trailing '.' FROM trim(trailing '0' FROM (a.stock - a.emprunte)::text)), a.fiche->>'unit';
  END IF;
  IF p_type = 'return' AND q > a.emprunte THEN RAISE EXCEPTION 'Quantité supérieure aux prêts en cours.'; END IF;
  IF p_type IN ('loan','return') AND a.fiche->>'type' <> 'equipment' THEN
    RAISE EXCEPTION 'Les prêts sont réservés au matériel durable.';
  END IF;
  IF p_type IN ('use','empty') AND a.fiche->>'type' = 'equipment' THEN
    RAISE EXCEPTION 'Utiliser la sortie définitive ou le prêt pour un matériel durable.';
  END IF;
  UPDATE public.labo_articles SET
    stock = stock + CASE p_type WHEN 'in' THEN q WHEN 'loan' THEN 0 WHEN 'return' THEN 0 ELSE -q END,
    emprunte = emprunte + CASE p_type WHEN 'loan' THEN q WHEN 'return' THEN -q ELSE 0 END,
    maj = now() WHERE id = p_article
  RETURNING stock, emprunte INTO s, e;
  INSERT INTO public.labo_mouvements(id, article_id, reception_id, action, quantite, libelle, unite, motif, auteur, auteur_email)
  VALUES (p_id, p_article, p_bl, p_type, q, a.fiche->>'name', a.fiche->>'unit', left(coalesce(p_note,''),500), p_auteur, coalesce(p_email,''))
  RETURNING * INTO m;
  RETURN jsonb_build_object('id', m.id, 'article', p_article, 'action', p_type, 'quantite', q,
    'unite', m.unite, 'libelle', m.libelle, 'auteur', m.auteur, 'horodatage', m.horodatage,
    'avant_stock', a.stock, 'avant_dispo', a.stock - a.emprunte,
    'stock', s, 'emprunte', e, 'disponible', s - e, 'duplicate', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.labo_bouger(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE personne text := public.labo_identite();
DECLARE u text;
DECLARE r jsonb;
BEGIN
  SELECT fiche->>'unit' INTO u FROM public.labo_articles WHERE id = (p->>'article')::uuid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Article introuvable.'; END IF;
  IF p->>'unit' IS DISTINCT FROM u THEN
    RAISE EXCEPTION 'L’unité de la fiche a changé. Rouvrir le mouvement.';
  END IF;
  r := public.labo_appliquer_mouvement((p->>'id')::uuid, (p->>'article')::uuid,
    p->>'action', (p->>'qty')::numeric, p->>'note', personne, lower(auth.jwt()->>'email'), NULL);
  IF NOT (r->>'duplicate')::boolean THEN
    UPDATE public.labo_sync SET revision = revision + 1 WHERE id = 1;
  END IF;
  RETURN r;
EXCEPTION WHEN invalid_text_representation THEN
  RAISE EXCEPTION 'Quantité ou identifiant invalide.';
END;
$$;

-- ───────────────────────── Fiches ─────────────────────────
CREATE OR REPLACE FUNCTION public.labo_enregistrer(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE personne text := public.labo_identite();
DECLARE op uuid := nullif(p->>'op','')::uuid;
DECLARE ident uuid := (p->>'id')::uuid;
DECLARE v integer;
DECLARE f jsonb := p->'item';
DECLARE old_f jsonb;
DECLARE existe boolean;
DECLARE r jsonb;
DECLARE ok boolean;
BEGIN
  IF op IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('labo-op:' || op::text, 0));
    SELECT resultat INTO r FROM public.labo_requetes WHERE id = op;
    IF FOUND THEN RETURN r || '{"duplicate":true}'::jsonb; END IF;
  END IF;
  PERFORM public.labo_verifier_fiche(f);
  ok := coalesce((f->>'verified')::boolean,false);
  SELECT fiche, version INTO old_f, v FROM public.labo_articles WHERE id = ident FOR UPDATE;
  existe := FOUND;
  -- La vérification est attribuée à la personne qui l’a confirmée.
  -- Elle est conservée si aucune donnée de sécurité n’a changé.
  IF ok AND existe AND coalesce((old_f->>'verified')::boolean,false)
     AND public.labo_securite_identique(old_f, f) AND coalesce(old_f->>'checkedBy','') <> '' THEN
    f := f || jsonb_build_object('checkedBy', old_f->>'checkedBy', 'checkedAt', old_f->'checkedAt');
  ELSIF ok THEN
    f := f || jsonb_build_object('checkedBy', personne, 'checkedAt', now());
  ELSE
    f := f || jsonb_build_object('checkedBy', '', 'checkedAt', '');
  END IF;
  IF existe THEN
    IF v <> coalesce((p->>'version')::integer,0) THEN
      RAISE EXCEPTION 'Cette fiche a été modifiée par un collègue. Fermer puis rouvrir la fiche.';
    END IF;
    IF old_f->>'unit' <> f->>'unit' AND EXISTS (
      SELECT 1 FROM public.labo_mouvements WHERE article_id = ident
    ) THEN RAISE EXCEPTION 'L’unité est fixée dès le premier mouvement. Créer une autre fiche pour une autre unité.'; END IF;
    IF f->>'type' <> 'equipment' AND EXISTS (
      SELECT 1 FROM public.labo_articles WHERE id = ident AND emprunte > 0
    ) THEN RAISE EXCEPTION 'Enregistrer les retours en cours avant de modifier la catégorie.'; END IF;
    UPDATE public.labo_articles SET fiche = f, version = v + 1, maj = now() WHERE id = ident;
    v := v + 1;
  ELSE
    INSERT INTO public.labo_articles(id, fiche) VALUES (ident, f);
    v := 1;
    IF coalesce((p->>'initial')::numeric,0) > 0 THEN
      PERFORM public.labo_appliquer_mouvement((p->>'movement')::uuid, ident, 'in',
        (p->>'initial')::numeric, 'Stock initial', personne, lower(auth.jwt()->>'email'), NULL);
    END IF;
  END IF;
  UPDATE public.labo_sync SET revision = revision + 1 WHERE id = 1;
  r := jsonb_build_object('id', ident, 'version', v, 'libelle', f->>'name', 'duplicate', false);
  IF op IS NOT NULL THEN
    INSERT INTO public.labo_requetes(id, nature, resultat, auteur) VALUES (op, 'enregistrer', r, personne);
  END IF;
  RETURN r;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Une fiche avec cette référence existe déjà pour ce fournisseur.';
END;
$$;

-- Associer une photo d’objet sans toucher au reste de la fiche ni à sa vérification.
CREATE OR REPLACE FUNCTION public.labo_associer_photo(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE personne text := public.labo_identite();
DECLARE op uuid := nullif(p->>'op','')::uuid;
DECLARE ident uuid := (p->>'article')::uuid;
DECLARE photo text := coalesce(p->>'photo','');
DECLARE r jsonb;
DECLARE v integer;
DECLARE nom text;
BEGIN
  IF op IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('labo-op:' || op::text, 0));
    SELECT resultat INTO r FROM public.labo_requetes WHERE id = op;
    IF FOUND THEN RETURN r || '{"duplicate":true}'::jsonb; END IF;
  END IF;
  IF photo !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$' THEN RAISE EXCEPTION 'Photo invalide.'; END IF;
  UPDATE public.labo_articles SET fiche = fiche || jsonb_build_object('photo', photo),
    version = version + 1, maj = now()
  WHERE id = ident RETURNING version, fiche->>'name' INTO v, nom;
  IF NOT FOUND THEN RAISE EXCEPTION 'Article introuvable.'; END IF;
  UPDATE public.labo_sync SET revision = revision + 1 WHERE id = 1;
  r := jsonb_build_object('id', ident, 'version', v, 'libelle', nom, 'auteur', personne, 'horodatage', now(), 'duplicate', false);
  IF op IS NOT NULL THEN
    INSERT INTO public.labo_requetes(id, nature, resultat, auteur) VALUES (op, 'photo', r, personne);
  END IF;
  RETURN r;
END;
$$;

-- ───────────────────────── Réceptions ─────────────────────────
CREATE OR REPLACE FUNCTION public.labo_receptionner(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE personne text := public.labo_identite();
DECLARE courriel text := lower(auth.jwt()->>'email');
DECLARE ident uuid := (p->>'id')::uuid;
DECLARE l jsonb;
DECLARE f jsonb;
DECLARE article uuid;
DECLARE u text;
DECLARE n integer := 0;
BEGIN
  -- Même bon envoyé deux fois (double appui, coupure réseau) : traité une seule fois.
  PERFORM pg_advisory_xact_lock(hashtextextended('labo-bl:' || ident::text, 0));
  IF EXISTS (SELECT 1 FROM public.labo_receptions WHERE id = ident) THEN
    RETURN jsonb_build_object('id', ident, 'duplicate', true,
      'lignes', (SELECT count(*) FROM public.labo_mouvements WHERE reception_id = ident));
  END IF;
  IF coalesce(length(btrim(p->>'supplier')),0) NOT BETWEEN 1 AND 250
    OR jsonb_typeof(p->'lines') <> 'array' OR jsonb_array_length(p->'lines') NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Indiquer le fournisseur et au moins une ligne valide.';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(p->'photos','[]')) x(k)
             WHERE k !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$') THEN
    RAISE EXCEPTION 'Photo du bon invalide.';
  END IF;
  INSERT INTO public.labo_receptions(id, fournisseur, numero, jour, photos, empreinte, auteur, auteur_email)
  VALUES (ident, btrim(p->>'supplier'), left(btrim(coalesce(p->>'number','')),200),
    (p->>'date')::date, coalesce(p->'photos','[]'), left(coalesce(p->>'hash',''),128), personne, courriel);
  -- Même ordre de verrouillage pour deux réceptions qui portent sur les mêmes articles.
  FOR l IN SELECT value FROM jsonb_array_elements(p->'lines') ORDER BY value->>'article'
  LOOP
    article := (l->>'article')::uuid;
    SELECT fiche->>'unit' INTO u FROM public.labo_articles WHERE id = article FOR UPDATE;
    IF NOT FOUND THEN
      f := l->'item';
      IF f IS NULL THEN RAISE EXCEPTION 'Fiche article introuvable.'; END IF;
      f := f || '{"verified":false,"checkedBy":""}'::jsonb;
      PERFORM public.labo_verifier_fiche(f);
      INSERT INTO public.labo_articles(id, fiche) VALUES (article, f);
    ELSIF u IS DISTINCT FROM l->>'unit' THEN
      RAISE EXCEPTION 'L’unité du bon diffère de l’unité de la fiche existante.';
    END IF;
    PERFORM public.labo_appliquer_mouvement((l->>'id')::uuid, article, 'in', (l->>'qty')::numeric,
      'Bon de livraison ' || coalesce(p->>'number',''), personne, courriel, ident);
    n := n + 1;
  END LOOP;
  UPDATE public.labo_sync SET revision = revision + 1 WHERE id = 1;
  RETURN jsonb_build_object('id', ident, 'duplicate', false, 'lignes', n, 'auteur', personne, 'horodatage', now());
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Bon déjà importé ou référence déjà présente. Vérifier les rapprochements.';
END;
$$;

-- ───────────────────────── Commandes ─────────────────────────
-- Montants calculés côté serveur (référence comptable) :
--   PU TTC = arrondi(PU HT × (1 + TVA)) ; total HT = arrondi(PU HT × qté) ; total TTC = arrondi(PU HT × qté × (1 + TVA)).
CREATE OR REPLACE FUNCTION public.labo_commander(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE personne text := public.labo_identite();
DECLARE op uuid := nullif(p->>'op','')::uuid;
DECLARE ident uuid := (p->>'id')::uuid;
DECLARE an integer := extract(year FROM now() AT TIME ZONE 'Europe/Paris')::integer;
DECLARE rg integer;
DECLARE l jsonb;
DECLARE out_l jsonb := '[]'::jsonb;
DECLARE pu numeric; q numeric; t numeric;
DECLARE ht numeric := 0; ttc numeric := 0;
DECLARE lht numeric; lttc numeric;
DECLARE r jsonb;
DECLARE disc text := coalesce(p->>'discipline','commun');
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('labo-cmd:' || ident::text, 0));
  SELECT to_jsonb(c) - 'auteur_email' INTO r FROM public.labo_commandes c WHERE id = ident;
  IF FOUND THEN RETURN r || '{"duplicate":true}'::jsonb; END IF;
  IF coalesce(length(btrim(p->>'supplier')),0) NOT BETWEEN 1 AND 250
    OR disc NOT IN ('svt','pc','commun')
    OR jsonb_typeof(p->'lines') <> 'array' OR jsonb_array_length(p->'lines') NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Indiquer le fournisseur et au moins une ligne de commande.';
  END IF;
  FOR l IN SELECT value FROM jsonb_array_elements(p->'lines')
  LOOP
    pu := (l->>'priceHT')::numeric; q := (l->>'qty')::numeric; t := (l->>'vat')::numeric;
    IF coalesce(length(btrim(l->>'name')),0) NOT BETWEEN 1 AND 250 OR length(coalesce(l->>'code','')) > 120
      OR pu IS NULL OR pu < 0 OR pu > 1000000 OR pu <> round(pu, 4)
      OR q IS NULL OR q <= 0 OR q > 1000000 OR q <> round(q, 3)
      OR t IS NULL OR t NOT IN (0, 2.1, 5.5, 10, 20) THEN
      RAISE EXCEPTION 'Ligne de commande invalide : %', coalesce(l->>'name','sans désignation');
    END IF;
    lht := round(pu * q, 2);
    lttc := round(pu * q * (1 + t / 100), 2);
    ht := ht + lht; ttc := ttc + lttc;
    out_l := out_l || jsonb_build_object('article', nullif(l->>'article',''), 'name', btrim(l->>'name'),
      'code', btrim(coalesce(l->>'code','')), 'unit', coalesce(l->>'unit',''), 'priceHT', pu, 'vat', t,
      'priceTTC', round(pu * (1 + t / 100), 2), 'qty', q, 'totalHT', lht, 'totalTTC', lttc);
  END LOOP;
  -- Mémoriser le dernier prix sur les fiches (ordre fixe des verrous), sans toucher à leur vérification FDS.
  FOR l IN SELECT value FROM jsonb_array_elements(out_l) WHERE value->>'article' IS NOT NULL ORDER BY value->>'article'
  LOOP
    UPDATE public.labo_articles SET fiche = fiche || jsonb_build_object('priceHT', (l->>'priceHT'), 'vat', (l->>'vat'))
    WHERE id = (l->>'article')::uuid;
  END LOOP;
  PERFORM pg_advisory_xact_lock(hashtextextended('labo-cmd-numero', 0));
  SELECT coalesce(max(rang), 0) + 1 INTO rg FROM public.labo_commandes WHERE annee = an;
  INSERT INTO public.labo_commandes(id, numero, annee, rang, fournisseur, discipline, lignes, total_ht, total_ttc, note, auteur, auteur_email)
  VALUES (ident, 'CMD-' || an || '-' || lpad(rg::text, 3, '0'), an, rg, btrim(p->>'supplier'), disc, out_l, ht, ttc,
    left(coalesce(p->>'note',''), 1000), personne, lower(auth.jwt()->>'email'));
  UPDATE public.labo_sync SET revision = revision + 1 WHERE id = 1;
  SELECT to_jsonb(c) - 'auteur_email' INTO r FROM public.labo_commandes c WHERE id = ident;
  RETURN r || '{"duplicate":false}'::jsonb;
EXCEPTION WHEN invalid_text_representation THEN
  RAISE EXCEPTION 'Montant, quantité ou identifiant invalide.';
END;
$$;

-- Coordonnées de l'établissement et logo, communs à tous les documents.
CREATE OR REPLACE FUNCTION public.labo_regler(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE personne text := public.labo_identite();
DECLARE v jsonb := coalesce(p->'settings','{}'::jsonb);
BEGIN
  IF jsonb_typeof(v) <> 'object' OR length(v::text) > 4000
    OR coalesce(v->>'logo','') !~ '^([0-9a-f-]{36}/[0-9a-f-]{36}\.jpg)?$' THEN
    RAISE EXCEPTION 'Paramètres invalides.';
  END IF;
  UPDATE public.labo_parametres SET valeurs = v || jsonb_build_object('majPar', personne, 'maj', now()) WHERE id = 1;
  UPDATE public.labo_sync SET revision = revision + 1 WHERE id = 1;
  RETURN v;
END;
$$;

-- ───────────────────────── Droits ─────────────────────────
REVOKE ALL ON FUNCTION public.labo_est_membre(), public.labo_identite(), public.labo_etat(),
  public.labo_journal(timestamptz,uuid), public.labo_verifier_fiche(jsonb), public.labo_ident(text),
  public.labo_securite_identique(jsonb,jsonb),
  public.labo_appliquer_mouvement(uuid,uuid,text,numeric,text,text,text,uuid),
  public.labo_enregistrer(jsonb), public.labo_bouger(jsonb), public.labo_receptionner(jsonb),
  public.labo_associer_photo(jsonb), public.labo_commander(jsonb), public.labo_regler(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.labo_est_membre(), public.labo_etat(), public.labo_journal(timestamptz,uuid),
  public.labo_enregistrer(jsonb), public.labo_bouger(jsonb), public.labo_receptionner(jsonb),
  public.labo_associer_photo(jsonb), public.labo_commander(jsonb), public.labo_regler(jsonb)
  TO authenticated;

COMMIT;

-- À personnaliser ensuite puis à exécuter séparément, avec les adresses réelles.
-- INSERT INTO public.labo_membres (email, nom) VALUES
--   ('adresse@exemple.fr', 'Prénom Nom')
-- ON CONFLICT (email) DO UPDATE SET nom = excluded.nom, actif = true;
