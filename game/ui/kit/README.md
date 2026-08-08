# Kit UI — réplique de Heat (Godot 4)

Zéro image produite. Tout est dessiné en code : `StyleBoxFlat` pour le carton,
`Label` pour la typo, `_draw()` pour les symboles, un shader de 20 lignes pour
le grain de papier.

## Où c'est installé

```
res://
├── data/
│   ├── palette.gd
│   └── card_data.gd
├── fonts/
│   ├── ArchivoBlack-Regular.ttf
│   ├── BarlowCondensed-Medium.ttf
│   ├── BarlowCondensed-Regular.ttf
│   └── OFL.txt
├── ui/kit/
│   ├── theme_builder.gd
│   ├── kerb.gd
│   ├── card.gd
│   ├── heat_gauge.gd
│   ├── ui_kit_demo.gd
│   └── ui_kit_demo.tscn
└── shaders/
    └── paper_grain.gdshader
```

Pour voir le rendu : ouvre `res://ui/kit/ui_kit_demo.tscn` et fais **F6**.

Les scripts utilisent `class_name`, donc aucun autoload n'est nécessaire.
La démo applique le thème sur son propre `Control` (pas sur `get_tree().root`),
donc elle ne repeint pas le reste du jeu.

## Direction artistique

**Palette** — cinq couleurs, pas une de plus. Asphalte, carton, rouge écurie,
bleu essence, moutarde. Tout passe par `palette.gd`.

**Typo** — `Archivo Black` pour les chiffres / titres, `Barlow Condensed Medium`
pour le texte. Les `.ttf` sont embarqués dans `res://fonts/` (licence OFL) et
chargés par `ThemeBuilder.display_font()` / `body_font()`.

**Élément signature** — la bande de vibreurs (`kerb.gd`). Elle revient partout :
bas des cartes, en-tête, séparateurs. Elle sait défiler (`animate()`), ce qui
donne une sensation de vitesse sans une seule frame d'animation.

**Grain** — un `ColorRect` plein écran par-dessus tout le reste. Le grain est
*fixe*, pas animé : un grain qui grouille fait « vidéo », un grain fixe fait
« imprimé ». C'est le détail qui fait le plus de différence pour l'ambiance
jeu de table.

## Ce que tu peux ajuster en premier

| Envie | Fichier | Quoi toucher |
|---|---|---|
| Changer l'ambiance complète | `data/palette.gd` | les constantes de couleur |
| Cartes plus grandes / petites | `ui/card.gd` | `SIZE_DEFAULT` |
| Éventail plus ou moins ouvert | `demo.gd` | `FAN_SPREAD`, `FAN_LIFT` |
| Grain plus marqué | `shaders/paper_grain.gdshader` | `grain_amount` |
| Nouveau type de carte | `data/card_data.gd` | l'enum `Kind` + `accent()` / `face()` |

## Symboles

`card.gd` dessine `flame`, `chevron` et `gear` à la main. Pour le reste, va
chercher sur **game-icons.net** : 4000+ SVG en noir et blanc sous licence CC-BY,
faits exactement pour ce genre de jeu. Godot 4 importe le SVG directement ; tu
les recolories avec `modulate` plutôt que de rééditer le fichier.

Attribution CC-BY : garde un écran de crédits avec le nom de l'auteur de chaque
icône utilisée.

## Prochaines briques, si ça te tente

- **La piste** — même approche : un `Node2D` par segment (droit, virage,
  chicane) assemblé bout à bout, avec `Line2D` pour le tracé et le `Kerb` pour
  les bordures. Beaucoup plus souple qu'une grosse image de circuit.
- **Un `Deck` / `Hand`** — un `Resource` qui contient le paquet et distribue des
  `CardData`, pour que ton chum branche sa logique de jeu dessus sans toucher au UI.
- **Un thème clair** — la palette étant centralisée, ça se fait en une passe.
