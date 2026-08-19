class_name JournalFormat
extends RefCounted

## Turns engine event_log lines into French BBCode for the UI journal.


static func to_bbcode(line: String) -> String:
	var fr := _translate(line)
	return _colorize(fr) + "\n"


static func _translate(line: String) -> String:
	var m: RegExMatch

	m = _re("^Race setup on (.+) \\((\\d+) laps\\), seed=(\\d+)$").search(line)
	if m:
		return "Course sur %s (%s tour(s)), graine %s" % [m.get_string(1), m.get_string(2), m.get_string(3)]

	m = _re("^(.+) pays 1 Heat for double shift$").search(line)
	if m:
		return "%s paie 1 Heat pour un double changement de rapport" % m.get_string(1)

	m = _re("^(.+) shifts to gear (\\d+)$").search(line)
	if m:
		return "%s passe en rapport %s" % [m.get_string(1), m.get_string(2)]

	m = _re("^All gears locked — play cards$").search(line)
	if m:
		return "Rapports verrouillés — jouez vos cartes"

	m = _re("^(.+) plays (\\d+) card\\(s\\)( \\(cluttered\\))?$").search(line)
	if m:
		var clutter := " (main encombrée)" if m.get_string(3) != "" else ""
		return "%s joue %s%s" % [m.get_string(1), _cards(m.get_string(2)), clutter]

	m = _re("^(.+) cluttered — no move, gear to 1$").search(line)
	if m:
		return "%s encombré — pas de déplacement, rapport 1" % m.get_string(1)

	m = _re("^(.+) resolves Stress -> Speed (\\d+)$").search(line)
	if m:
		return "%s résout Stress → Speed %s" % [m.get_string(1), m.get_string(2)]

	m = _re("^(.+) reveals speed (\\d+) and moves$").search(line)
	if m:
		return "%s révèle Speed %s et avance" % [m.get_string(1), m.get_string(2)]

	m = _re("^(.+) cools down (\\d+)$").search(line)
	if m:
		return "%s met %s Heat en cooldown" % [m.get_string(1), m.get_string(2)]

	m = _re("^(.+) uses adrenaline \\+1 speed$").search(line)
	if m:
		return "%s utilise l'adrénaline (+1 Speed)" % m.get_string(1)

	m = _re("^(.+) boosts for \\+(\\d+)$").search(line)
	if m:
		return "%s booste pour +%s" % [m.get_string(1), m.get_string(2)]

	m = _re("^(.+) blocked — lands at progress (\\d+) spot (\\d+)$").search(line)
	if m:
		return "%s bloqué — s'arrête progress %s, spot %s" % [
			m.get_string(1), m.get_string(2), m.get_string(3)
		]

	m = _re("^(.+) crossed the finish line \\(progress (\\d+), spot (\\d+)\\)$").search(line)
	if m:
		return "%s franchit la ligne (progress %s, spot %s)" % [
			m.get_string(1), m.get_string(2), m.get_string(3)
		]

	m = _re("^(.+) slipstreams \\+(\\d+)$").search(line)
	if m:
		return "%s prend l'aspiration (+%s)" % [m.get_string(1), m.get_string(2)]

	m = _re("^(.+) clears corner (.+) \\(speed (\\d+) <= (\\d+)\\)$").search(line)
	if m:
		return "%s passe le virage %s (speed %s ≤ %s)" % [
			m.get_string(1), m.get_string(2), m.get_string(3), m.get_string(4)
		]

	m = _re("^(.+) pays (\\d+) Heat at corner (.+)$").search(line)
	if m:
		return "%s paie %s Heat au virage %s" % [m.get_string(1), m.get_string(2), m.get_string(3)]

	m = _re("^(.+) spins out at (.+) — gear 1, \\+(\\d+) Stress$").search(line)
	if m:
		return "%s part en tête-à-queue à %s — rapport 1, +%s Stress" % [
			m.get_string(1), m.get_string(2), m.get_string(3)
		]

	m = _re("^(.+) discards (\\d+) card\\(s\\)$").search(line)
	if m:
		return "%s défausse %s" % [m.get_string(1), _cards(m.get_string(2))]

	m = _re("^(.+) replenishes hand \\((\\d+)\\)$").search(line)
	if m:
		return "%s pioche jusqu'à %s cartes" % [m.get_string(1), m.get_string(2)]

	m = _re("^(.+) placed #(\\d+) \\(progress (\\d+), spot (\\d+)\\)$").search(line)
	if m:
		return "%s classé #%s (progress %s, spot %s)" % [
			m.get_string(1), m.get_string(2), m.get_string(3), m.get_string(4)
		]

	m = _re("^New round — shift gears$").search(line)
	if m:
		return "Nouveau tour — changez de rapport"

	m = _re("^Race over$").search(line)
	if m:
		return "Course terminée"

	m = _re("^Garage draft round (\\d+)$").search(line)
	if m:
		return "Draft garage — ronde %s" % m.get_string(1)

	m = _re("^Garage draft complete — review loadouts$").search(line)
	if m:
		return "Draft garage terminé — vérifiez les voitures"

	m = _re("^Garage draft complete — shift gears$").search(line)
	if m:
		return "Draft garage terminé — changez de rapport"

	m = _re("^(.+) is ready$").search(line)
	if m:
		return "%s est prêt" % m.get_string(1)

	m = _re("^(.+) drafts (.+)$").search(line)
	if m:
		return "%s choisit %s" % [m.get_string(1), m.get_string(2)]

	m = _re("^(.+) quick-start upgrades$").search(line)
	if m:
		return "%s reçoit 3 améliorations (quick start)" % m.get_string(1)

	m = _re("^(.+) Direct Play (.+) \\+(\\d+)$").search(line)
	if m:
		return "%s Direct Play %s +%s" % [m.get_string(1), m.get_string(2), m.get_string(3)]

	m = _re("^(.+) accelerate \\+(\\d+)$").search(line)
	if m:
		return "%s accélère +%s" % [m.get_string(1), m.get_string(2)]

	return line


static func _colorize(line: String) -> String:
	var lower := line.to_lower()
	if "heat" in lower:
		return "[color=#ff9a5c]%s[/color]" % line
	if "tête-à-queue" in lower or "spin" in lower:
		return "[color=#ff6b6b]%s[/color]" % line
	if "ligne" in lower or "classé" in lower or "terminée" in lower:
		return "[color=#ffe066]%s[/color]" % line
	if "aspiration" in lower or "slipstream" in lower:
		return "[color=#74c0fc]%s[/color]" % line
	if "stress" in lower:
		return "[color=#d0bfff]%s[/color]" % line
	if "boost" in lower or "adrénaline" in lower or "adrenaline" in lower:
		return "[color=#b2f2bb]%s[/color]" % line
	if "révèle" in lower or "reveals" in lower:
		return "[color=#a5d8ff]%s[/color]" % line
	return line


static func is_reveal_line(line: String) -> bool:
	return "reveals speed" in line or "révèle Speed" in line


static func reveal_banner_text(line: String) -> String:
	var m := _re("reveals speed (\\d+)").search(line)
	if m == null:
		m = _re("révèle Speed (\\d+)").search(line)
	var fr := _translate(line)
	if m:
		return fr
	return fr


## "1 carte" / "3 cartes" — the engine emits a raw count, the journal reads as prose.
static func _cards(count: String) -> String:
	return "1 carte" if count == "1" else "%s cartes" % count


static func _re(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re
