extends Node

const ITEM_BOX_SCENE = preload("res://ui/player_stats/item_box_base.tscn")
const ABILITY_BOX_SCENE = preload("res://ui/player_stats/ability_box_base.tscn")
const ITEM_ICON_SIZE = Vector2(24, 24)
const ABILITY_ICON_SIZE = Vector2(48, 48)
const PASSIVE_SIZE = Vector2(24, 24)

var waiting_for_character = false
var first_draw_iteration = true

var upgrade_icon: Texture2D

var _map: Node
var _character: Unit

@onready var player_icon := $CharacterUI/PortraitBorder/Portrait
@onready var money_count := $GameStats/Money
@onready var kda_display := $GameStats/KDA
@onready var cs_display := $GameStats/CS

@onready var hp_bar := $CharacterUI/HealthMana/HealthBar
@onready var mana_bar := $CharacterUI/HealthMana/ManaBar

@onready var player_display := $CharacterUI/Level
@onready var player_level_number := $CharacterUI/Level/LevelNumber

@onready var spells_container := $CharacterUI/Items/HBoxContainer/SpellsPanel/SpellsContainer
@onready
var active_items_container := $CharacterUI/Items/HBoxContainer/ActiveItemPanel/ActiveItemGrid
@onready
var passive_items_container := $CharacterUI/Items/HBoxContainer/PassiveItemPanel/PassiveItemGrid

@onready var abilities_container := $CharacterUI/PanelContainer/AbilitiesHbox
@onready var passive_ability_container := $CharacterUI/Passive


func _ready() -> void:
	if Config.is_dedicated_server:
		return

	if _map == null:
		print("map not set")
		return

	var raw_upgrade_icon = _get_texture(
		Identifier.for_resource("texture://openchamp:units/characters/ability_up")
	)

	upgrade_icon = ImageTexture.create_from_image(raw_upgrade_icon.get_image())
	upgrade_icon.set_size_override(Vector2i(48, 48))

	# Todo get the current player and set the icons to the
	# the ones for the actual character of the current player
	call_deferred("_set_icons")


func _process(_delta: float) -> void:
	if Config.is_dedicated_server:
		return

	if waiting_for_character:
		return

	if _character == null:
		call_deferred("_set_icons")
		return

	money_count.text = str(_character.current_gold)
	kda_display.text = (
		str(_character.kills) + "/" + str(_character.deaths) + "/" + str(_character.assists)
	)
	cs_display.text = str(_character.minion_kills)

	hp_bar.value = _character.current_stats.health
	hp_bar.max_value = _character.maximum_stats.health

	mana_bar.value = _character.current_stats.mana
	mana_bar.max_value = _character.maximum_stats.mana

	player_level_number.text = str(_character.level)
	player_display.tooltip_text = (
		"XP: " + str(_character.level_exp) + "/" + str(_character.required_exp)
	)

	if first_draw_iteration:
		_update_items()
		_update_abilities()
		first_draw_iteration = false

	if _character.items_changed:
		_character.items_changed = false
		_update_items()


func _update_items():
	var passive_item_icons = passive_items_container.get_children()
	for item in passive_item_icons:
		passive_items_container.remove_child(item)
		item.queue_free()

	var active_item_icons = active_items_container.get_children()
	for item in active_item_icons:
		active_items_container.remove_child(item)
		item.queue_free()

	for index in range(_character.passive_item_slots):
		var item_box: Node = null
		if index < _character.item_slots_passive.size():
			var item = _character.item_slots_passive[index] as Item
			var icon_id := item.get_texture_resource() as Identifier
			if icon_id != null and icon_id.is_valid():
				var icon = _get_texture(icon_id)
				if icon != null:
					item_box = _create_item_box(icon, item.get_tooltip_string(_character), "")

		if item_box == null:
			item_box = _create_item_box(null, "", "")
			if item_box == null:
				print("Failed to create item box")
				continue

		passive_items_container.add_child(item_box)

	for index in range(_character.active_item_slots):
		var item_box: Node = null
		if index < _character.item_slots_active.size():
			var item = _character.item_slots_active[index] as Item
			var icon_id := item.get_texture_resource() as Identifier
			if icon_id and icon_id.is_valid():
				var icon = _get_texture(item)
				if icon != null:
					item_box = _create_item_box(icon, item.get_tooltip_string(_character), "")

		if item_box == null:
			item_box = _create_item_box(null, "", "")
			if item_box == null:
				print("Failed to create item box")
				continue

		active_items_container.add_child(item_box)


func _update_abilities():
	var ability_icons = abilities_container.get_children()
	for ability in ability_icons:
		abilities_container.remove_child(ability)
		ability.queue_free()

	var passive_ability_icons = passive_ability_container.get_children()
	for ability in passive_ability_icons:
		passive_ability_container.remove_child(ability)
		ability.queue_free()

	var passive_ability := _character.abilities["passive"] as Ability
	if passive_ability != null:
		var passive_icon_id = passive_ability.get_texture_resource() as Identifier
		if passive_icon_id != null and passive_icon_id.is_valid():
			var passive_icon = _get_texture(passive_icon_id)
			var passive_tooltip = passive_ability.get_tooltip_string(_character)
			var passive_ability_box = _create_ability_box(passive_icon, passive_tooltip, "", true)
			if passive_ability_box != null:
				passive_ability_container.add_child(passive_ability_box)

	var ability_names = _character.abilities.keys()
	for ability_name in ability_names:
		ability_name = ability_name as String

		if not ability_name.begins_with("ability_"):
			continue

		var ability = _character.abilities[ability_name] as Ability
		if ability == null:
			print("Failed to get ability %s" % ability_name)
			continue

		var icon_id = ability.get_texture_resource() as Identifier
		if icon_id == null or not icon_id.is_valid():
			print("Icon for ability %s not found" % ability_name)
			continue

		var icon = _get_texture(icon_id)
		if icon == null:
			print("Icon for ability %s not loaded: %s" % [ability_name, icon_id.to_string()])
			continue

		var tooltip = ability.get_tooltip_string(_character)
		var ability_box = _create_ability_box(icon, tooltip, ability.get_cost())
		if ability_box == null:
			print("Failed to create ability box for %s" % ability_name)
			continue

		var ability_container := VBoxContainer.new()
		abilities_container.size_flags_vertical = Control.SIZE_SHRINK_END
		ability_container.set_alignment(2)#ALIGN_END

		if _character.ability_upgrade_points > 0 && ability.can_upgrade():
			var upgrade_button = Button.new()

			upgrade_button.icon = upgrade_icon
			upgrade_button.custom_minimum_size = ABILITY_ICON_SIZE
			upgrade_button.size = ABILITY_ICON_SIZE
			upgrade_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			upgrade_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			upgrade_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			upgrade_button.flat = true
			upgrade_button.expand_icon = true

			var upgrade_function = _map.rpc_id.bind(
				get_multiplayer_authority(), "upgrade_ability", ability_name
			)
			upgrade_button.pressed.connect(upgrade_function)
			ability_container.add_child(upgrade_button)

		ability_container.add_child(ability_box)
		abilities_container.add_child(ability_container)


func _get_texture(icon_id: Identifier = null) -> Texture2D:
	var icon_path = AssetIndexer.get_asset_path(icon_id)
	if icon_path == "":
		return null

	var icon = load(icon_path)
	if icon == null:
		return null

	return icon


func _create_item_box(icon: Texture2D, tooltip: String, text: String):
	var item_box = ITEM_BOX_SCENE.instantiate()
	if item_box == null:
		print("Failed to instantiate item box")
		return null

	var item_box_bg = item_box.get_node("AspectBox/Background")
	if item_box_bg == null:
		print("Failed to get item box bg")
		return item_box

	if icon != null:
		var item_box_icon = TextureRect.new()
		item_box_icon.texture = icon
		item_box_icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
		item_box_icon.stretch_mode = TextureRect.STRETCH_SCALE
		item_box_icon.custom_minimum_size = ITEM_ICON_SIZE

		if tooltip != "":
			item_box_icon.tooltip_text = tooltip
			item_box_icon.mouse_filter = Control.MOUSE_FILTER_PASS

		item_box_bg.add_child(item_box_icon)

	if text != "":
		var item_box_label = RichTextLabel.new()
		item_box_label.text = text
		item_box_bg.add_child(item_box_label)

	return item_box


func _create_ability_box(icon: Texture2D, tooltip: String, text: String, passive: bool = false):
	var ability_box = ABILITY_BOX_SCENE.instantiate()
	if ability_box == null:
		print("Failed to instantiate ability box")
		return null

	var aspect_box = ability_box.get_node("AspectBox")
	var ability_box_bg = ability_box.get_node("AspectBox/Background")
	
	if aspect_box == null || ability_box_bg == null:
		print("Failed to get ability box")
		return ability_box

	if icon != null:
		var ability_box_icon = TextureRect.new()
		ability_box_icon.texture = icon
		ability_box_icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
		ability_box_icon.stretch_mode = TextureRect.STRETCH_SCALE
		if passive:
			ability_box_icon.custom_minimum_size = PASSIVE_SIZE
			ability_box.custom_minimum_size = PASSIVE_SIZE
			ability_box_bg.custom_minimum_size = PASSIVE_SIZE
		else:
			ability_box_icon.custom_minimum_size = ABILITY_ICON_SIZE
			ability_box.custom_minimum_size = ABILITY_ICON_SIZE
			ability_box_bg.custom_minimum_size = ABILITY_ICON_SIZE

		if tooltip != "" && text == "":
			ability_box_icon.tooltip_text = tooltip
			ability_box_icon.mouse_filter = Control.MOUSE_FILTER_PASS

		ability_box_bg.add_child(ability_box_icon)

	if text != "":
		var item_box_label = RichTextLabel.new()
		item_box_label.bbcode_enabled = true
		item_box_label.text = "[font_size=10][right]"+text+"[/right]"
		if tooltip != "":
			item_box_label.tooltip_text = tooltip
			item_box_label.mouse_filter = Control.MOUSE_FILTER_PASS
		aspect_box.add_child(item_box_label)
		aspect_box.get_children()

	return ability_box


func _set_icons():
	if waiting_for_character:
		return

	waiting_for_character = true

	while _character == null:
		var returned_char = _map.get_character(multiplayer.get_unique_id())
		if typeof(returned_char) == TYPE_BOOL:
			print("Character not found")
		elif returned_char != null:
			_character = returned_char as Unit
			break

		print("Character not found")

	var player_icon_id = RegistryManager.units().get_element(_character.unit_id).get_icon_id()
	if player_icon_id == null:
		print("Icon not found")
		return

	var _player_icon = load(player_icon_id.get_resource_id())
	if _player_icon == null:
		print("Icon not loaded")
		return

	_character.current_stats_changed.connect(func(_old_stats, _new_stats): self._update_abilities())

	player_icon.texture = _player_icon

	if _character.has_mana:
		mana_bar.show()
	else:
		mana_bar.hide()

	player_display.mouse_filter = Control.MOUSE_FILTER_STOP

	waiting_for_character = false
