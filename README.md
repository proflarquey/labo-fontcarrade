# Labo Fontcarrade — inventaire des laboratoires de SVT et de physique-chimie

Application web d’inventaire pour les laboratoires du collège Fontcarrade. Elle est pensée pour un téléphone tenu d’une main, debout, sans formation. Un seul fichier `index.html` est publié sur GitHub Pages ou sur la Forge des communs numériques éducatifs. Le stock est partagé avec une base Supabase.

Ouvrir `index.html` sans configuration lance la **démonstration** : articles fictifs, rien n’est partagé.

## Ce que fait la version 2

| Geste | Sur le téléphone |
|---|---|
| **Retirer une unité** | « Utiliser » sur la ligne, puis « Retirer 1 boîte ». Deux appuis. La feuille montre le nom, l’unité, le disponible et le rangement avant le second appui. |
| **Autre quantité** | « Autre quantité » ouvre le clavier numérique (virgule acceptée), les boutons +1/−1 et le micro. La quantité dictée (« trois virgule cinq ») est affichée pour relecture. Elle n’est jamais validée automatiquement. |
| **Résultat** | Après chaque validation, l’écran indique ce qui a été enregistré, l’avant et l’après (« 3 → 2 boîtes »), l’auteur et l’heure. Un bouton « Annuler ce mouvement » enregistre le mouvement inverse dans le journal. |
| **Réceptionner** | « Scanner un bon » ouvre directement la caméra. La lecture se fait sur l’appareil. Chaque ligne du bon devient une carte : extrait de la photo, référence, quantité, unité, désignation et fiche rapprochée. Les champs incertains sont en orange (lecture peu sûre, quantité illisible, unité absente, O/0 ambigu…). On corrige ou on touche « C’est correct ». Le reste de la ligne ne bouge pas. La validation reste bloquée tant qu’un doute subsiste. |
| **Photo d’objet** | « Photo d’objet » ouvre la caméra et lit l’étiquette (et le code-barres si le téléphone sait le lire). L’application propose les fiches correspondantes, avec la raison du rapprochement (même référence, même n° CAS, nom proche). On associe la photo en un appui ou on crée une fiche préremplie (désignation, référence, concentration, n° CAS, mentions H). |
| **Entrée / sortie manuelle** | Recherche de l’article, puis la même feuille que « Utiliser » : entrée, sortie définitive, consommation, contenant vidé, prêt, retour. |
| **Recherche** | Toujours en haut de l’accueil. Elle porte sur le nom, la référence, le rangement, le fournisseur et le n° CAS. Chaque résultat affiche le disponible et le rangement. Filtres : stock bas, FDS à vérifier, discipline, rangement, catégorie. |
| **Hors connexion** | Un mouvement validé sans réseau est conservé sur l’appareil, puis envoyé automatiquement au retour du réseau, une seule fois. Son résultat s’affiche alors. Les saisies longues (réception, fiche, photo d’objet, bon de commande) sont enregistrées au fil de la frappe. Elles survivent à une coupure ou à un rechargement, et un bandeau propose de les reprendre. |

### Produits chimiques

La fiche est reliée à la **FDS exacte** : on recopie le fournisseur, la référence et la concentration **inscrits sur la FDS**, et l’application les compare à ceux de l’article. Elle présente ensuite :
- l’étiquetage (rubrique 2.2) : pictogrammes, mention d’avertissement, mentions H ;
- le stockage (rubrique 7.2) ;
- les incompatibilités (rubrique 10.5) ;
- le compartiment réel, constaté sur place, avec la famille de rangement.

La liste **« Reste à vérifier »** énumère ce qui manque ou ne concorde pas. Elle signale aussi un voisin incompatible dans le même compartiment et une FDS révisée il y a plus de trois ans.

La case de vérification ne s’active que lorsque tout concorde. Le serveur refait le contrôle et enregistre le nom de la personne qui a vérifié. Si un champ de sécurité change ensuite (compartiment, concentration…), la vérification est à refaire. Une modification du seuil ou de la photo la conserve.

### Bons de commande (SVT et physique-chimie)

- **Création** : un bon par fournisseur. Les articles sous le seuil de ce fournisseur sont proposés automatiquement. On peut ajouter un article de l’inventaire ou une ligne libre.
- **Contenu** : article, code produit, PU HT, TVA, PU TTC, quantité, total HT, total TTC ; totaux HT, TVA et TTC ; discipline et demandeur ; cadres de visa du demandeur, du gestionnaire et du chef d’établissement (ordonnateur).
- **Numérotation et montants** : la numérotation (CMD-2026-001…) et les montants sont calculés par le serveur, au centime, sans doublon même si deux collègues valident en même temps.
- **Export** : **PDF** ou **Excel (.xlsx)**, puis **Télécharger** ou **Partager**. Partager ouvre le menu du téléphone (messagerie, Drive, ENT…). Sur un ordinateur, le fichier est téléchargé.
- **Fichier Excel** : il contient des formules ; si la gestionnaire change une quantité, les totaux se recalculent.
- **Logo et coordonnées** : on les saisit une fois dans *Commandes → Logo et coordonnées*. Ils valent pour toute l’équipe. **Le logo du collège n’est pas fourni** : le charger depuis le fichier officiel de l’établissement.
- **Prix mémorisé** : le dernier prix HT de chaque article est enregistré sur sa fiche.

### Étiquettes

Les étiquettes s’impriment sur planche A4. Formats proposés :
- 99,1 × 67,7 mm (8 par page) ;
- 99,1 × 38,1 mm (14 par page) ;
- 70 × 37 mm (24 par page) ;
- 63,5 × 38,1 mm (21 par page) ;
- 38,1 × 21,2 mm (65 par page), pour l’identification seule.

On choisit la première case libre pour réutiliser une planche entamée.

L’**étiquette de danger** n’est produite qu’à partir d’une FDS vérifiée. Elle reprend :
- le nom, la concentration et le n° CAS ;
- les pictogrammes et la mention d’avertissement ;
- les mentions H telles que saisies : les recopier en entier depuis la FDS ;
- le fournisseur, la référence et la date de la FDS ;
- une ligne « Ouvert le ».

Si les mentions ne tiennent pas, l’application refuse et demande un format plus grand plutôt que de tronquer. Sinon, elle propose une étiquette d’identification. Faire une impression test sur papier ordinaire : l’alignement varie selon la marque de la planche.

## Hébergement en France ou en Europe

L’application se compose de deux parties.

| Partie | Contenu | Où l’héberger |
|---|---|---|
| **Interface** (`index.html`) | Code et icônes, **aucune donnée** | GitHub Pages, ou la **Forge des communs numériques éducatifs** (forge.apps.education.fr, service du ministère, GitLab Pages). |
| **Base** (Supabase) | Articles, mouvements, noms, photos, FDS | **Option A** : Supabase en ligne, région **West EU (Paris), eu-west-3**, à choisir à la création du projet. Le projet ne peut pas changer de région ensuite. Données stockées en France, mais par une société américaine. **Option B, la plus souveraine** : Supabase installé avec Docker chez un hébergeur français (OVH, Scaleway…). C’est le même logiciel, sans télémétrie, mais il faut assurer soi-même la maintenance et les sauvegardes. |

L’interface accepte les deux options. On indique l’adresse https du serveur et la clé **publique** (`sb_publishable_…` ou clé `anon`). L’application refuse une clé `service_role`.

## Mise en ligne

### 1. Préparer la base

Dans **SQL Editor** (ou `psql` en auto-hébergé), exécuter `base_partagee.sql`.

Une base créée avec la version 1 est **mise à jour sans perte** : le script ajoute :
- les tables des commandes, des paramètres et des requêtes déjà traitées ;
- l’adresse de l’auteur sur chaque mouvement ;
- les nouvelles fonctions.

### 2. Autoriser les collègues

**Authentication → Users → Add user** : un compte par collègue, avec un mot de passe distinct. Désactiver les inscriptions publiques. Puis, dans SQL Editor :

```sql
INSERT INTO public.labo_membres (email, nom) VALUES
  ('prenom1.nom1@exemple.fr', 'Prénom Nom'),
  ('prenom2.nom2@exemple.fr', 'Prénom Nom')
ON CONFLICT (email) DO UPDATE SET nom = excluded.nom, actif = true;
```

Pour retirer un accès : `UPDATE public.labo_membres SET actif = false WHERE email = '…';`. Le journal conserve les opérations passées.

### 3. Mot de passe oublié et lien de connexion

Dans **Authentication → URL Configuration**, renseigner l’adresse exacte de la page publiée comme **Site URL** et dans **Redirect URLs**. Configurer un **SMTP** pour que les courriels partent vers toute l’équipe. Le bouton « Mot de passe oublié ? » envoie alors un lien. Il ouvre l’application sur l’écran « Nouveau mot de passe » (10 caractères au moins).

### 4. Publier l’interface

Dans `index.html`, modifier seulement la ligne repérée `id="labo-config"` :

```html
<script id="labo-config" type="application/json">{"url":"https://VOTRE-PROJET.supabase.co","key":"sb_publishable_VOTRE_CLE"}</script>
```

- **GitHub** : déposer `index.html` à la racine de `main`, puis aller dans *Settings → Pages → Deploy from a branch → main / (root)*.
- **Forge** : déposer `index.html` dans un dossier `public/`, avec un fichier `.gitlab-ci.yml` de publication Pages, comme pour un site HTML simple.

Ne jamais déposer dans le dépôt de clé secrète, de bon de livraison, de FDS ou de sauvegarde.

### 5. Vérifier

Ouvrir la page sur deux téléphones avec deux comptes. Créer un article de 2 boîtes sur le premier, puis vérifier :
- l’article apparaît sur le second ;
- un retrait sur chaque téléphone donne 0, avec un mouvement attribué à chacun dans le Journal ;
- un troisième retrait est refusé avec « Stock disponible insuffisant ».

## RGPD (repères, à valider avec le délégué à la protection des données)

- **Données traitées** : nom et adresse des personnels, mouvements attribués. **Aucune donnée d’élève.**
- **Responsable du traitement** : le chef d’établissement. Inscrire le traitement au registre et informer les collègues.
- **Conservation** : fixer une durée. Au départ d’un collègue, désactiver son compte ; le journal reste attribué à son nom.
- **Diffusion à d’autres établissements** : une base par établissement, ou une future version multi-établissements avec un contrat de sous-traitance.

## Contrôles effectués avant livraison

- **Base PostgreSQL** (36 vérifications, répétées 5 fois sans échec) :
  - 2 comptes × 15 retraits simultanés sur un stock de 10 : exactement 10 acceptés, stock final 0, aucun négatif, 10 lignes de journal attribuées ;
  - même mouvement envoyé 6 fois en parallèle : appliqué une fois ;
  - décimaux en mL concurrents : stock exact ;
  - prêts et retours concurrents ;
  - même bon validé deux fois en même temps : une seule entrée ;
  - compte non membre refusé ;
  - FDS d’une autre concentration refusée, vérification attribuée à son auteur ;
  - 20 bons de commande simultanés : numéros uniques et continus, montants au centime.
- **Interface sur téléphone 360 px** (53 vérifications) :
  - les trois parcours, dont un bon réel de 3 lignes lu par l’OCR avec une quantité illisible détectée puis corrigée ;
  - la dictée de 3,5 mL ;
  - un prêt puis son retour ;
  - un rechargement en pleine réception sans perte des corrections ;
  - aucun défilement horizontal, toutes les cibles d’au moins 44 px ;
  - PDF du bon et des étiquettes valides ;
  - fichier Excel recalculé à l’identique par LibreOffice.
- **Deux collègues via l’interface** (16 vérifications) :
  - retrait concurrent sur le dernier article, avec refus clair ;
  - coupure réseau puis envoi automatique unique ;
  - attribution de chaque mouvement ;
  - bon de commande partagé.

Les scripts sont dans `tests/`.

**Non testé ici** :
- le canal temps réel de Supabase (l’actualisation de secours toutes les 15 secondes, elle, a été testée) ;
- la dictée sur un vrai micro (simulée) ;
- l’alignement sur une planche d’étiquettes physique.

## Sources et composants

- [INRS ED 4406 · Pictogrammes CLP](https://www.inrs.fr/media.html?refINRS=ED+4406) · [INRS ED 6015 · Stockage au laboratoire](https://www.inrs.fr/media.html?refINRS=ED+6015) · [Règlement (UE) 2020/878 · FDS](https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX%3A32020R0878)
- [Supabase · Régions](https://supabase.com/docs/guides/platform/regions) · [Supabase · Auto-hébergement avec Docker](https://supabase.com/docs/guides/self-hosting/docker) · [Forge des communs numériques éducatifs](https://forge.apps.education.fr/)
- OCR : [Tesseract.js](https://github.com/naptha/tesseract.js), [Tesseract.js-core](https://github.com/naptha/tesseract.js-core), [tessdata_fast](https://github.com/tesseract-ocr/tessdata_fast). Icônes Lucide. Pictogrammes SGH de Wikimedia Commons. Les avis de licence sont dans `LICENSES.txt`.
- Les générateurs PDF et Excel sont écrits pour cette application. Ils n’utilisent aucune bibliothèque externe et ne font aucun appel réseau. Les chasses de caractères Helvetica proviennent des métriques AFM standard d’Adobe.
