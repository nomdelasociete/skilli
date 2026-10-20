# skil.li — Halo menthe / verre

Direction retenue le 10 octobre 2026 : **S en ruban plié, point séparé en bas à droite, verre légèrement givré sur halo menthe/pétrole animé lentement**. Le balayage lumineux qui traversait le S a été explicitement rejeté puis retiré. Les reflets restent attachés aux plis ; seule la lumière du halo évolue.

Ce dossier est la source de référence pour la marque et ses exports. Pour les
choix du site livré, suivre le document lié dans la section Site.

## Fichiers

| Fichier | Usage |
| --- | --- |
| `halo-menthe-glass.png` | Composition fixe 1024 × 1024, fond opaque carré non masqué. À utiliser dans les settings et comme poster/fallback web. |
| `index.html` + `halo-menthe.js` | Référence animée autonome, sans dépendance ni appel réseau externe. Prévisualisation et export PNG. |
| `ribbon-glass.svg` | Faces translucides et arêtes du ruban + point. Ce SVG seul ne reproduit pas la réfraction : il doit être composé sur le fond et la couche réfractée. |
| `ribbon-mask.svg` | Silhouette blanche servant de masque à la couche réfractée. |
| `menu-template.svg` | Silhouette noire 18 × 18 sur transparence, dédiée au menu macOS. |
| `ribbon-frosted-fallback.svg` | Ancien ruban opaque/satiné, conservé en secours ; ce n’est pas la matière finale retenue. |
| `comparison-reference.png` | Capture de la comparaison approuvée : ancienne matière à gauche, verre retenu à droite. Référence visuelle, pas un asset à afficher dans l’app. |
| `3d/` | Le S en 3D : un seul ruban de verre réellement plié, verre transparent façon *liquid glass*, point en sphère (**v4 retenue**). Blender, GLB pour three.js, environnement HDR, PNG transparents, rendus. Voir `3d/README.md`. |

## Prévisualiser / exporter

Depuis la racine du dépôt :

```sh
python3 -m http.server 8768 --bind 127.0.0.1 --directory assets/brand
```

Ouvrir `http://127.0.0.1:8768/`. « Pause » fige le halo ; « Exporter le PNG 1024 » compose l’image puis affiche un lien de téléchargement et un aperçu. Le PNG livré est un instant figé du halo ; la position de la lumière peut donc différer au fil de l’animation. L’export reste carré, sans coins arrondis ; les coins visibles dans la page appartiennent au conteneur.

## Site

Pour le site livré (typographies, textes, animations, navigation et démos), lire
[les décisions validées](../../docs/website-design.md). Ce kit reste la référence
pour la géométrie et la matière du logo ; le document du site régit sa mise en page.

Reprendre la composition de `.stage`, ses styles et le shader, ou commencer par le PNG. Le ruban occupe 72 % du cadre carré, avec des marges internes déjà présentes dans son viewBox. Conserver les proportions, les plis et le point. Ne pas étirer le S et ne pas déplacer le point pour en faire une ponctuation de texte.

La composition comporte : fond WebGL, même fond avec coordonnées décalées sous le masque (réfraction simulée), faces SVG translucides, ombre et lumière d’ambiance. Les deux canvases partagent exactement le même temps. La géométrie ne bouge pas. Aucun reflet indépendant ne doit balayer la lettre, aucun scintillement ni rotation permanente.

Le shader est original à cette étude, sans code ni dépendance OpenShaders. Il simule une matière ; ce n’est pas le moteur Liquid Glass d’Apple.

La démo est une référence de rendu, pas un composant de production : avant intégration, isoler les sélecteurs, préfixer les identifiants SVG si plusieurs logos sont inline et exposer un cycle de montage/démontage. Limiter la résolution selon la taille affichée (la démo utilise 1024 pour exporter), suspendre hors écran via IntersectionObserver et détruire les ressources WebGL au démontage. Retirer `preserveDrawingBuffer` si l’export n’est plus nécessaire. Respecter `prefers-reduced-motion`, y compris ses changements en cours de session, et utiliser le PNG si WebGL manque ou perd son contexte. La démo respecte la préférence initiale et ne redessine pas pendant la pause ni lorsque le document est caché.

Pour un logo porteur de sens : nom accessible « skil.li ». Pour un logo décoratif à côté du nom : `aria-hidden="true"`/alt vide ; ne pas faire annoncer séparément les couches.

## Settings macOS

Utiliser la composition PNG statique dans un asset catalog, redimensionnée pour la taille affichée. Elle conserve la matière retenue sans moteur web ni animation permanente. Le fond est volontairement opaque : ne pas l’utiliser comme un pictogramme template. Ne pas placer de texte directement sur les zones lumineuses.

Aucun WebView, runtime JavaScript ou shader web ne doit être ajouté au launcher ou à la barre des menus pour ce logo. Le PNG suffit aussi comme première intégration des settings.

En tête de Settings → Général (13 octobre 2026, demandé par JB) : le S seul, `3d/skilli-mark-halo@2x.png` (halo cuit dans le verre, lisible en clair comme en sombre), s'incline vers la souris comme le hero du site (±10° en largeur, ±6° en hauteur, amorti). C'est une transformation 3D de l'image fixe, rien qui tourne seul : pas de boucle, pas de reflet qui balaie la lettre, à plat avec « Réduire les animations ». La petite icône en haut de la barre latérale a disparu : à 30 pt, le S ne se lisait pas.

## Barre des menus

Utiliser `menu-template.svg` comme source pour produire un PDF vectoriel ou des PNG @1x/@2x compatibles avec le pipeline d’assets natif. Ne pas supposer que NSImage charge un SVG brut. Configurer le résultat avec `isTemplate = true`, autour de 18 pt, pour que macOS choisisse la couleur en clair/sombre. Aucun fond, dégradé, verre ou animation ici. Vérifier à 16, 18 et 22 pt en clair et sombre ; préserver le petit point et les ouvertures des plis.

## Icône d’application / Icon Composer

L’icône est `Sources/Skilli/Resources/AppIcon.icon`, un projet Icon Composer (retenu le 2026-10-18 : le rendu 3D précédent était illisible en petit). Deux calques en verre, le S et le point, tirés des tracés de `menu-template.svg` ; fond en dégradé pétrole (clair) et pétrole profond avec un S menthe (sombre). Le système applique masque, ombre et reflets : ne rien cuire dans les SVG.

Après toute modification, vérifier les rendus Default, Dark, TintedLight et ClearLight, et la lisibilité à 16 et 32 px :

```sh
ictool="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
"$ictool" Sources/Skilli/Resources/AppIcon.icon --export-image --output-file icon-Dark.png \
  --platform macOS --rendition Dark --width 512 --height 512 --scale 1
```

## Fenêtre du DMG

`dmg/background.png` et `@2x` (640 × 360 pt), produits par `dmg/make_background.py` ; `script/release/dmg_settings.py` place l’app et Applications dessus. Finder écrit les noms sous les icônes en noir (clair) ou en blanc (sombre) : la bande où ils tombent garde une luminance relative proche de 0,18, lisible dans les deux cas.

## Décisions à préserver

- Halo menthe/pétrole retenu ; aurore cobalt et opaline ne sont pas la direction choisie.
- Verre légèrement givré, plis lisibles, point dans la même matière.
- Pas de balayage lumineux sur le S.
- Le signe reste un S et un point ; ne pas forcer deux « i » supplémentaires dans sa géométrie.
- La version animée concerne le site ; le menu reste simple et statique.
- Logo 3D : la **v4** de `3d/` est retenue (12 octobre 2026) : ruban unique plié en Z aux plis ronds, verre transparent épais à bords en lentille, surface polie, point en sphère. Les v1–v3 restent dans `3d/versions/` pour mémoire.

## Validation du kit

Prévisualisation vérifiée dans le navigateur Codex : rendu du shader, pause/reprise et composition PNG 1024. Aucun message d’erreur JavaScript observé. SVG parsés comme XML et chemins locaux vérifiés. L’intégration AppKit/Icon Composer et les variantes système restent à valider par l’agent intégrateur. Tests et benchmark natifs indisponibles sur la base `main` de cette PR (elle ne contient pas encore `script/build_and_run.sh` ni le projet de l’application).
