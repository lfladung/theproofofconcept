extends SceneTree

const IC := preload("res://scripts/infusion/infusion_constants.gd")
const IM := preload("res://scripts/infusion/infusion_manager.gd")

## V1 stack math only. Parse: `.\tools\run_headless.ps1 -CheckOnly -Script res://tools/tmp_infusion_manager_harness.gd`
## Run: `.\tools\run_headless.ps1 -Script res://tools/tmp_infusion_manager_harness.gd`

func _fail(msg: String) -> void:
	push_error("INFUSION_HARNESS_FAIL: %s" % msg)
	quit(1)


func _init() -> void:
	call_deferred(&"_run")


func _thr(mgr, pillar: StringName) -> int:
	return int(mgr.call(&"get_pillar_threshold", pillar))


func _run() -> void:
	var host := Node.new()
	host.name = "FakePlayer"
	root.add_child(host)

	var mgr = IM.new()
	mgr.auto_bind_run_state = false
	mgr.require_server_for_mutations = false
	mgr.warn_unknown_pillars = false
	host.add_child(mgr)
	await process_frame

	var edge := IC.PILLAR_EDGE
	var T := IC.InfusionThreshold
	if _thr(mgr, edge) != int(T.INACTIVE):
		_fail("0 stack = inactive")
	mgr.add_infusion(edge, IC.STACK_MINI, IC.SourceKind.MINI)
	if _thr(mgr, edge) != int(T.INACTIVE):
		_fail("0.5 stack = inactive")
	mgr.add_infusion(edge, IC.STACK_MINI, IC.SourceKind.MINI)
	if _thr(mgr, edge) != int(T.BASELINE):
		_fail("two mini = baseline (1.0)")
	mgr.clear_run_infusions()
	mgr.add_infusion(edge, IC.STACK_NORMAL, IC.SourceKind.NORMAL)
	if _thr(mgr, edge) != int(T.BASELINE):
		_fail("1.0 stack = baseline")
	var id_mid := mgr.add_infusion(edge, IC.STACK_NORMAL, IC.SourceKind.NORMAL)
	if _thr(mgr, edge) != int(T.ESCALATED):
		_fail("2.0 stack = escalated")
	mgr.add_infusion(edge, IC.STACK_NORMAL, IC.SourceKind.NORMAL)
	if _thr(mgr, edge) != int(T.EXPRESSION):
		_fail("3.0 stack = expression")
	if not mgr.remove_infusion_by_id(id_mid):
		_fail("remove failed")
	if _thr(mgr, edge) != int(T.ESCALATED):
		_fail("removing one normal should drop 3.0 -> 2.0 escalated")

	print("INFUSION_HARNESS_OK")
	quit(0)
