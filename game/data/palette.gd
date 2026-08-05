class_name Palette
extends RefCounted

## Palette unique du jeu. Toute couleur affichée doit venir d'ici.
## Si tu veux changer l'ambiance du jeu au complet, c'est le seul fichier a toucher.

# --- Fonds ---
const ASPHALT := Color(0.106, 0.114, 0.129)   # #1B1D21  fond general
const INK := Color(0.090, 0.094, 0.106)       # #17181B  texte fonce, ombres

# --- Matiere ---
const CARDBOARD := Color(0.863, 0.827, 0.745) # #DCD3BE  carton de carte
const CARDBOARD_DARK := Color(0.784, 0.745, 0.659) # #C8BEA8  tranche / verso
const SMOKE := Color(0.431, 0.416, 0.373)     # #6E6A5F  texte secondaire

# --- Accents ---
const RACE_RED := Color(0.753, 0.224, 0.169)  # #C0392B  vitesse, danger, vibreurs
const FUEL_BLUE := Color(0.122, 0.306, 0.420) # #1F4E6B  calme, moteur froid
const MUSTARD := Color(0.910, 0.639, 0.090)   # #E8A317  attention, surchauffe imminente

## Retourne la couleur d'ecurie pour un index de joueur.
static func team(index: int) -> Color:
	var colors := [
		Color(0.753, 0.224, 0.169), # rouge ecurie
		Color(0.122, 0.306, 0.420), # bleu ecurie
		Color(0.910, 0.639, 0.090), # moutarde
		Color(0.263, 0.435, 0.294), # vert anglais
		Color(0.451, 0.286, 0.510), # prune
		Color(0.933, 0.933, 0.914), # blanc course
	]
	return colors[index % colors.size()]


## Couleur de la jauge selon le ratio de chaleur (0.0 = froid, 1.0 = moteur mort).
static func heat_color(ratio: float) -> Color:
	if ratio < 0.5:
		return FUEL_BLUE.lerp(MUSTARD, ratio / 0.5)
	return MUSTARD.lerp(RACE_RED, (ratio - 0.5) / 0.5)
