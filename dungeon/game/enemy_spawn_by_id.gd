extends Object
class_name EnemySpawnById

## Maps Room Editor `enemy_id` strings (see `default_room_piece_catalog.tres`) to spawn scenes.

const DASHER_SCENE := preload("res://scenes/entities/dasher.tscn")
const ARROW_TOWER_SCENE := preload("res://scenes/entities/arrow_tower.tscn")
const SKEWER_SCENE := preload("res://scenes/entities/skewer.tscn")
const GLAIVER_SCENE := preload("res://scenes/entities/glaiver.tscn")
const RAZORFORM_SCENE := preload("res://scenes/entities/razorform.tscn")
const SCRAMBLER_SCENE := preload("res://scenes/entities/scrambler.tscn")
const FLOW_DASHER_SCENE := preload("res://scenes/entities/flow_dasher.tscn")
const FLOWFORM_SCENE := preload("res://scenes/entities/flowform.tscn")
const STUMBLER_SCENE := preload("res://scenes/entities/stumbler.tscn")
const SHIELDWALL_SCENE := preload("res://scenes/entities/shieldwall.tscn")
const WARDEN_SCENE := preload("res://scenes/entities/warden.tscn")
const SPLITTER_SCENE := preload("res://scenes/entities/splitter.tscn")
const ECHOFORM_SCENE := preload("res://scenes/entities/echoform.tscn")
const TRIAD_SCENE := preload("res://scenes/entities/triad.tscn")
const LURKER_SCENE := preload("res://scenes/entities/lurker.tscn")
const LEECHER_SCENE := preload("res://scenes/entities/leecher.tscn")
const BINDER_SCENE := preload("res://scenes/entities/binder.tscn")
const FIZZLER_SCENE := preload("res://scenes/entities/fizzler.tscn")
const BURSTER_SCENE := preload("res://scenes/entities/burster.tscn")
const DETONATOR_SCENE := preload("res://scenes/entities/detonator.tscn")
const ECHO_SPLINTER_SCENE := preload("res://scenes/entities/echo_splinter.tscn")
const ECHO_UNIT_SCENE := preload("res://scenes/entities/echo_unit.tscn")


static func primary_family_scenes() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = [
		SKEWER_SCENE,
		GLAIVER_SCENE,
		RAZORFORM_SCENE,
		SCRAMBLER_SCENE,
		FLOW_DASHER_SCENE,
		FLOWFORM_SCENE,
		STUMBLER_SCENE,
		SHIELDWALL_SCENE,
		WARDEN_SCENE,
		SPLITTER_SCENE,
		ECHOFORM_SCENE,
		TRIAD_SCENE,
		LURKER_SCENE,
		LEECHER_SCENE,
		BINDER_SCENE,
		FIZZLER_SCENE,
		BURSTER_SCENE,
		DETONATOR_SCENE,
	]
	return scenes


static func scene_for_enemy_id(enemy_id: StringName) -> PackedScene:
	var key := String(enemy_id).strip_edges().to_lower()
	match key:
		"", "default":
			return null
		"dasher":
			return DASHER_SCENE
		"arrow_tower":
			return ARROW_TOWER_SCENE
		"skewer":
			return SKEWER_SCENE
		"glaiver":
			return GLAIVER_SCENE
		"razorform":
			return RAZORFORM_SCENE
		"scrambler":
			return SCRAMBLER_SCENE
		"flow_dasher":
			return FLOW_DASHER_SCENE
		"flowform":
			return FLOWFORM_SCENE
		"stumbler":
			return STUMBLER_SCENE
		"shieldwall":
			return SHIELDWALL_SCENE
		"warden":
			return WARDEN_SCENE
		"splitter":
			return SPLITTER_SCENE
		"echoform":
			return ECHOFORM_SCENE
		"triad":
			return TRIAD_SCENE
		"lurker":
			return LURKER_SCENE
		"leecher":
			return LEECHER_SCENE
		"binder":
			return BINDER_SCENE
		"fizzler":
			return FIZZLER_SCENE
		"burster":
			return BURSTER_SCENE
		"detonator":
			return DETONATOR_SCENE
		"echo_splinter":
			return ECHO_SPLINTER_SCENE
		"echo_unit":
			return ECHO_UNIT_SCENE
		_:
			return null
