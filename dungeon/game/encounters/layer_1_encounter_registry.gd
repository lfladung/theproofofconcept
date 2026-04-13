extends Object
class_name Layer1EncounterRegistry

const EncounterTemplateScript = preload("res://dungeon/game/encounters/encounter_template.gd")


static func templates() -> Array:
	var T = EncounterTemplateScript
	return [
		T.make(&"flow_basics", "Flow Basics", 1, _tags(["open", "small", "low_intensity", "flow"]), [
			T.enemy(&"scrambler", 5),
		]),
		T.make(&"surge_basics", "Surge Basics", 1, _tags(["open", "medium", "surge"]), [
			T.enemy(&"fizzler", 6, 8),
		]),
		T.make(&"edge_basics", "Edge Basics", 1, _tags(["corridor", "small", "low_intensity", "edge"]), [
			T.enemy(&"skewer", 4),
		]),
		T.make(&"volley_basics", "Volley Basics", 1, _tags(["open", "medium", "range"]), [
			T.enemy(&"spitter_flow", 4),
		]),
		T.make(&"phase_basics", "Phase Basics", 1, _tags(["open", "small", "phase", "low_intensity"]), [
			T.enemy(&"lurker", 2, 3),
		]),
		T.make(&"mass_basics", "Mass Basics", 1, _tags(["corridor", "small", "mass", "low_intensity"]), [
			T.enemy(&"stumbler", 2),
		]),
		T.make(&"echo_basics", "Echo Basics", 1, _tags(["open", "small", "echo"]), [
			T.enemy(&"splitter", 1),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"movement_projectiles", "Movement + Projectiles", 1, _tags(["open", "medium", "flow", "range"]), [
			T.enemy(&"scrambler", 3),
			T.enemy(&"spitter_flow", 2),
		]),
		T.make(&"movement_precision", "Movement + Precision", 1, _tags(["corridor", "medium", "flow", "edge"]), [
			T.enemy(&"scrambler", 3),
			T.enemy(&"skewer", 2),
		]),
		T.make(&"aoe_opportunity", "AoE Opportunity", 1, _tags(["open", "medium", "surge"]), [
			T.enemy(&"fizzler", 5),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"sustain_pressure", "Sustain Pressure", 1, _tags(["open", "medium", "echo"]), [
			T.enemy(&"splitter", 1),
			T.enemy(&"scrambler", 3),
		]),
		T.make(&"phase_distraction", "Phase Distraction", 1, _tags(["open", "medium", "phase"]), [
			T.enemy(&"lurker", 2),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"zone_awareness", "Zone Awareness", 1, _tags(["open", "medium", "mass", "range"]), [
			T.enemy(&"spitter_mass", 3),
			T.enemy(&"stumbler", 1),
		]),
		T.make(&"first_dash_threat", "First Dash Threat", 1, _tags(["open", "medium", "flow"]), [
			T.enemy(&"dasher", 1),
			T.enemy(&"scrambler", 3),
		]),
		T.make(&"first_flank_puzzle", "First Flank Puzzle", 1, _tags(["corridor", "medium", "mass", "range"]), [
			T.enemy(&"shieldwall", 1),
			T.enemy(&"spitter_flow", 2),
		]),
		T.make(&"first_precision_punish", "First Precision Punish", 1, _tags(["corridor", "medium", "edge"]), [
			T.enemy(&"glaiver", 1),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"first_timer_threat", "First Timer Threat", 1, _tags(["open", "medium", "surge"]), [
			T.enemy(&"burster", 1),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"first_control_loss", "First Control Loss", 1, _tags(["open", "medium", "phase"]), [
			T.enemy(&"leecher", 1),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"first_spread_threat", "First Spread Threat", 1, _tags(["open", "medium", "range", "edge"]), [
			T.enemy(&"volley_edge", 1),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"flank_under_pressure", "Flank Under Pressure", 1, _tags(["corridor", "large", "mass", "flow"]), [
			T.enemy(&"shieldwall", 1),
			T.enemy(&"scrambler", 2),
			T.enemy(&"spitter_flow", 1),
		]),
		T.make(&"dash_zone", "Dash + Zone", 1, _tags(["open", "large", "flow", "mass", "range"]), [
			T.enemy(&"dasher", 1),
			T.enemy(&"spitter_mass", 2),
			T.enemy(&"scrambler", 1),
		]),
		T.make(&"precision_range", "Precision + Range", 1, _tags(["open", "large", "edge", "range"]), [
			T.enemy(&"glaiver", 1),
			T.enemy(&"spitter_flow", 2),
			T.enemy(&"scrambler", 1),
		]),
		T.make(&"splitter_protected", "Splitter Protected", 1, _tags(["corridor", "large", "echo", "mass"]), [
			T.enemy(&"splitter", 1),
			T.enemy(&"shieldwall", 1),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"phase_pressure", "Phase + Pressure", 1, _tags(["open", "large", "phase", "range"]), [
			T.enemy(&"lurker", 2),
			T.enemy(&"scrambler", 2),
			T.enemy(&"spitter_flow", 1),
		]),
		T.make(&"burster_chaos", "Burster Chaos", 1, _tags(["open", "medium", "surge"]), [
			T.enemy(&"burster", 1),
			T.enemy(&"scrambler", 3),
		]),
		T.make(&"movement_lock_test", "Movement Lock Test", 1, _tags(["corridor", "large", "mass", "edge"]), [
			T.enemy(&"shieldwall", 1),
			T.enemy(&"glaiver", 1),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"multi_timing_problem", "Multi-Timing Problem", 1, _tags(["open", "large", "flow", "range"]), [
			T.enemy(&"dasher", 1),
			T.enemy(&"spitter_flow", 2),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"panic_check", "Panic Check", 1, _tags(["corridor", "large", "phase", "edge"]), [
			T.enemy(&"leecher", 1),
			T.enemy(&"skewer", 1),
			T.enemy(&"scrambler", 2),
		]),
		T.make(&"zone_pressure_stack", "Zone + Pressure Stack", 1, _tags(["open", "large", "mass", "range"]), [
			T.enemy(&"spitter_mass", 2),
			T.enemy(&"scrambler", 2),
			T.enemy(&"stumbler", 1),
		]),
		T.make(&"layer_1_final_exam", "Layer 1 Final Exam", 1, _tags(["open", "large", "high_intensity"]), [
			T.choice([&"shieldwall", &"dasher"]),
			T.choice([&"glaiver", &"volley_edge"]),
			T.enemy(&"scrambler", 2),
		]),
	]


static func _tags(values: Array[String]) -> PackedStringArray:
	var out := PackedStringArray()
	for value in values:
		out.append(value)
	return out
