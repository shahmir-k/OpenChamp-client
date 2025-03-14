class_name Ability
extends Node

var _display_id: Identifier
var _texture_id: Identifier

var _can_levelup: bool = false
var _level: int = -1
var _ability_levels: Array[ActionEffect] = []
var _current_effect: ActionEffect = null

var _connected_unit: Unit = null


static func from_dict(_dict: Dictionary) -> Ability:
	if not _dict.has("display_id"):
		print("Could not create action effect from dictionary. Dictionary has no display_id key.")
		return null

	var ability_instance := Ability.new()

	ability_instance._display_id = Identifier.from_string(str(_dict["display_id"]))
	if not ability_instance._display_id.is_valid():
		print("Could not create ability from dictionary. Could not load data.")
		return null

	ability_instance._texture_id = Identifier.for_resource("texture://" + str(_dict["texture_id"]))

	var has_upgrades := JsonHelper.get_optional_bool(_dict, "has_upgrades", false)
	ability_instance._can_levelup = has_upgrades

	var base_values := _dict["base_values"] as Dictionary
	if base_values == null:
		print("Could not create ability from dictionary. Could not load data.")
		return null

	if not has_upgrades:
		var ability_effect := ActionEffect.from_dict(base_values)
		if ability_effect == null:
			print("Could not create ability from dictionary. Could not load data.")
			return null

		ability_effect.name = ability_instance._display_id.to_string()
		ability_instance._ability_levels.append(ability_effect)
		ability_instance._level = 0
		ability_instance._current_effect = ability_effect

		return ability_instance

	var ability_levels := _dict["ability_data"] as Array
	if ability_levels == null:
		print("Could not create ability from dictionary. Could not load data.")
		return null

	for ability_level_num in range(ability_levels.size()):
		var ability_data := ability_levels[ability_level_num] as Dictionary
		if ability_data == null:
			print("Could not create ability from dictionary. Could not load data.")
			return null

		ability_data.merge(base_values, true)

		var ability_effect := ActionEffect.from_dict(ability_data, true)
		if ability_effect == null:
			print("Could not create ability from dictionary. Could not load data.")
			return null

		ability_effect.name = (
			ability_instance._display_id.to_string() + "_" + str(ability_level_num)
		)
		ability_instance._ability_levels.append(ability_effect)

	if not _dict.has("display_id"):
		print("Could not create action effect from dictionary. Dictionary has no display_id key.")
		return null

	return ability_instance


func get_copy() -> Ability:
	var new_ability := Ability.new()

	new_ability._display_id = _display_id
	new_ability._texture_id = _texture_id
	new_ability._can_levelup = _can_levelup
	new_ability._level = _level

	for _ability_level in _ability_levels:
		var new_ability_level = _ability_level.get_copy()
		new_ability_level.name = _ability_level.name
		new_ability._ability_levels.append(new_ability_level)

	if _current_effect != null:
		for ability in new_ability._ability_levels:
			if ability.name == _current_effect.name:
				new_ability._current_effect = ability
				break

	return new_ability


func get_level() -> int:
	return _level


func get_cast_range() -> int:
	if _current_effect == null:
		return 0

	var active_effect := _current_effect as ActiveActionEffect
	if active_effect == null:
		return 0

	if active_effect.use_attack_range:
		return _connected_unit.current_stats.attack_range

	return int(active_effect.casting_range)


func get_texture_resource() -> Identifier:
	return _texture_id


func get_tooltip_string(character: Unit) -> String:
	var tooltip_string = ""
	var can_be_upgraded = can_upgrade()

	var display_level = _level + 1
	if _current_effect == null:
		display_level = 0

	var ability_name = tr("UNIT:%s:NAME" % _display_id.to_string())
	if can_be_upgraded:
		tooltip_string += "%s (%d)\n" % [ability_name, display_level]
	else:
		tooltip_string += "%s\n" % ability_name

	var ability_lore = tr("UNIT:%s:LORE" % _display_id.to_string())
	tooltip_string += "%s\n\n" % ability_lore

	if _current_effect:
		var current_effect_desc = _current_effect.get_description_string(character, "UNIT")
		tooltip_string += "Current Effect:\n%s\n\n" % current_effect_desc

	if can_be_upgraded:
		var next_effect_desc = _ability_levels[_level + 1].get_description_string(character, "UNIT")
		tooltip_string += "Next Effect:\n%s" % next_effect_desc

	return tooltip_string


func get_desctiption_strings(_caster: Unit = null) -> Dictionary:
	var ability_descriptions: Dictionary = {}

	return ability_descriptions


func get_ability_type() -> ActionEffect.AbilityType:
	if _current_effect == null:
		return ActionEffect.AbilityType.PASSIVE

	return _current_effect.get_ability_type()


func get_activation_state() -> ActionEffect.ActivationState:
	if _current_effect == null:
		return ActionEffect.ActivationState.NONE

	var activatable_effect := _current_effect as ActiveActionEffect
	if activatable_effect == null:
		return ActionEffect.ActivationState.NONE

	return activatable_effect.get_activation_state()


func try_activate(target = null) -> ActionEffect.ActivationState:
	if _current_effect == null:
		print("Could not activate ability. Ability has no effect.")
		return ActionEffect.ActivationState.NONE

	var activatable_effect := _current_effect as ActiveActionEffect
	if activatable_effect == null:
		print("Could not activate ability. Ability is not an active ability.")
		return ActionEffect.ActivationState.NONE

	return activatable_effect.activate(_connected_unit, target)


func _ready() -> void:
	var parent_node: Node = self
	while _connected_unit == null:
		parent_node = parent_node.get_parent()
		_connected_unit = parent_node as Unit

	if _current_effect != null:
		add_child(_current_effect)
		_current_effect.connect_to_unit(_connected_unit)


func can_upgrade() -> bool:
	if not _can_levelup:
		return false

	return _level + 1 < _ability_levels.size()


func upgrade() -> bool:
	if not _can_levelup:
		print("Could not upgrade ability. Ability has no upgrades.")
		return false

	if not (_level + 1 < _ability_levels.size()):
		print("Could not upgrade ability. Ability is already at max level.")
		return false

	if _current_effect != null:
		_current_effect.disconnect_from_unit(_connected_unit)
		remove_child(_current_effect)
		_current_effect = null

	_level += 1
	_current_effect = _ability_levels[_level]

	add_child(_current_effect)
	_current_effect.connect_to_unit(_connected_unit)

	return true
	
func get_cost() -> String:
	if _current_effect != null:
		var action_effect = _current_effect as ActiveActionEffect
		return str(action_effect.cost)
	else:
		var action_effect = _ability_levels[0] as ActiveActionEffect
		return str(action_effect.cost)
