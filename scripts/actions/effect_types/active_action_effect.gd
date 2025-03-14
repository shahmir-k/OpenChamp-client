class_name ActiveActionEffect
extends ActionEffect

var attack_speed_scaled: bool = false
var windup_ratio: float = 0.2

var in_casting_preview: bool = false
var casting_range: float = 0.0
var use_attack_range: bool = false
var cost: int = 0

var channel_time: float = 0.0
var active_time: float = 0.0
var cooldown_time: float = 0.0

var scaling_string: String = ""
var scaling_calc = null
var scaling_display = null

var cooldown_timer := Timer.new()

var _current_haste: float = 0.0


func init_from_dict(_dict: Dictionary, _is_ability: bool = false) -> bool:
	if not super(_dict, _is_ability):
		return false

	attack_speed_scaled = JsonHelper.get_optional_bool(_dict, "as_scaled", false)
	windup_ratio = JsonHelper.get_optional_number(_dict, "windup_ratio", 0.0)

	if not attack_speed_scaled:
		if not _dict.has("cooldown"):
			print(
				"Could not create ActiveActionEffect from dictionary. Missing required keys (cooldown)."
			)
			return false

	if not _dict.has("scaling"):
		print(
			"Could not create ActiveActionEffect from dictionary. Missing required keys (scaling)."
		)
		return false

	scaling_string = str(_dict["scaling"])
	var scaling_funcs = ScalingsBuilder.build_scaling_function(scaling_string)
	if scaling_funcs == null:
		print(
			"Could not create ActiveActionEffect from dictionary. Could not build scaling function."
		)
		return false

	scaling_calc = scaling_funcs[0]
	scaling_display = scaling_funcs[1]

	use_attack_range = JsonHelper.get_optional_bool(_dict, "use_attack_range", false)
	casting_range = JsonHelper.get_optional_number(_dict, "casting_range", 0.0)
	cost = JsonHelper.get_optional_number(_dict, "cost", 0)

	cooldown_time = JsonHelper.get_optional_number(_dict, "cooldown", 0.0)
	channel_time = JsonHelper.get_optional_number(_dict, "channel_time", 0.0)
	active_time = JsonHelper.get_optional_number(_dict, "active_time", 0.0)

	_activation_state = ActivationState.READY

	return true


func get_copy(new_effect: ActionEffect = null) -> ActionEffect:
	if new_effect == null:
		new_effect = ActiveActionEffect.new()

	new_effect = super(new_effect)
	var new_fx := new_effect as ActiveActionEffect

	new_fx.attack_speed_scaled = attack_speed_scaled
	new_fx.windup_ratio = windup_ratio

	new_fx.in_casting_preview = in_casting_preview
	new_fx.casting_range = casting_range
	new_fx.use_attack_range = use_attack_range
	new_fx.cost = cost

	new_fx.scaling_string = scaling_string
	new_fx.scaling_calc = scaling_calc
	new_fx.scaling_display = scaling_display

	new_fx.channel_time = channel_time
	new_fx.active_time = active_time
	new_fx.cooldown_time = cooldown_time

	return new_fx


func start_preview_cast(_caster: Unit) -> void:
	print("Not implemented. Needs to be implemented in the subclass.")


func stop_preview_cast(_caster: Unit) -> void:
	print("Not implemented. Needs to be implemented in the subclass.")


func activate(caster: Unit, target) -> ActivationState:
	if caster.current_stats.mana >= cost:
		match _activation_state:
			ActivationState.NONE:
				print("Could not activate ability. Ability has no activation state.")
				return ActivationState.NONE

			ActivationState.COOLDOWN, ActivationState.CHANNELING, ActivationState.ACTIVE:
				return _activation_state

			ActivationState.READY:
				_start_targeting(caster)

			ActivationState.TARGETING:
				_finish_targeting(caster, target)

			_:
				print("Could not activate ability. Unknown activation state.")

	return _activation_state


func interrupt(caster: Unit):
	match _activation_state:
		ActivationState.TARGETING:
			_activation_state = ActivationState.READY

		ActivationState.CHANNELING:
			_activation_state = ActivationState.READY

		ActivationState.ACTIVE:
			_activation_state = ActivationState.COOLDOWN
			_finish_active(caster, null)
		_:
			pass


func _start_targeting(caster: Unit) -> bool:
	_activation_state = ActivationState.TARGETING
	if _ability_type == AbilityType.AUTO_TARGETED:
		return _finish_targeting(caster, null)

	return true


func _finish_targeting(caster: Unit, target) -> bool:
	return _start_channeling(caster, target)


func _start_channeling(caster: Unit, target) -> bool:
	caster.spend_mana(cost)
	_activation_state = ActivationState.CHANNELING

	var final_channel_time: float = channel_time

	if attack_speed_scaled:
		var attack_time = float(100.0 / caster.current_stats.attack_speed)
		cooldown_timer.set_wait_time(attack_time * (1.0 - windup_ratio))

		channel_time = attack_time * windup_ratio

	get_tree().create_timer(final_channel_time).timeout.connect(
		_finish_channeling.bind(caster.get_path(), target.get_path())
	)

	return true


func _finish_channeling(caster_path: NodePath, target_path: NodePath) -> void:
	var caster_unit = get_node(caster_path) as Unit
	var target_unit = get_node(target_path) as Unit
	if target_unit:
		caster_unit.targeted_cast_finished.emit(caster_unit, target_unit, _effect_source)

	_start_active(caster_unit, target_unit)


func _start_active(caster: Unit, _target) -> void:
	if active_time <= 0.001:
		_finish_active(caster, _target)
		return

	_activation_state = ActivationState.ACTIVE

	get_tree().create_timer(active_time).timeout.connect(_finish_active.bind(caster, _target))


func _finish_active(caster: Unit, _target) -> void:
	if _activation_state == ActivationState.COOLDOWN or _activation_state == ActivationState.READY:
		return

	_current_haste = float(caster.current_stats.ability_haste)
	_start_cooldown()


func _start_cooldown() -> void:
	_activation_state = ActivationState.COOLDOWN

	if not attack_speed_scaled:
		var ability_rate: float = 1.0 + _current_haste / 100.0
		cooldown_timer.set_wait_time(cooldown_time / ability_rate)

	cooldown_timer.start()


func _on_cooldown_finished() -> void:
	_activation_state = ActivationState.READY


func connect_to_unit(_unit: Unit) -> void:
	_unit.current_stats_changed.connect(_update_haste)


func disconnect_from_unit(_unit: Unit) -> void:
	_unit.current_stats_changed.disconnect(_update_haste)


func _update_haste(_old_stats: StatCollection, new_stats: StatCollection) -> void:
	_current_haste = float(new_stats.ability_haste)


func _ready() -> void:
	if cooldown_time > 0.0:
		cooldown_timer.set_wait_time(cooldown_time)
	cooldown_timer.name = "Cooldown Timer"
	cooldown_timer.set_one_shot(true)
	cooldown_timer.timeout.connect(_on_cooldown_finished)
	add_child(cooldown_timer)
