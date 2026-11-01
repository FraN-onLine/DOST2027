extends Control

# The lobby, in two columns.
#
#   Left:  the roster - MAX_PLAYERS fixed slots, so the table's size reads at a
#          glance. A filled slot shows the mortal's god icon in a frame of that
#          god's accent, a swatch of the bandana colour that player wears on the
#          field, the name, and a gold HOST nameplate for peer 1; an empty one is a
#          dashed outline still "Waiting for a mortal...". YOUR slot also carries
#          the bandana picker: one swatch per colour, a colour another player holds
#          greyed out with a padlock; pressing a free one asks the host for it
#          (Network.choose_bandana_color) and the roster comes back with the answer.
#   Right: "You" (name + UPDATE, the god icon picker as a row of icon buttons)
#          and "The run" (the run summary and OPTIONS).
#   Top right: the lobby ID as a big key, with COPY (host only).
#   Bottom: LEAVE (ghost, left) and START GAME (the one gold primary, right).
#          While START is disabled the caption beside it says why - a disabled
#          button that does not say why is a dead end.

const EMPTY_TEXT := "Waiting for a mortal..."
const SLOT_ICON := Vector2(32, 32)
const COPIED_SECONDS := 1.5

@onready var player_list_vbox = $Page/VBox/Scroll/Columns/Roster/VBox/PlayerListVBox
@onready var roster_label: Label = $Page/VBox/Scroll/Columns/Roster/VBox/PlayerListLabel
@onready var name_input = $Page/VBox/Scroll/Columns/Side/YouCard/VBox/NameRow/NameInput
@onready var change_name_button = $Page/VBox/Scroll/Columns/Side/YouCard/VBox/NameRow/ChangeNameButton
@onready var god_icon_row: HBoxContainer = $Page/VBox/Scroll/Columns/Side/YouCard/VBox/GodIconRow
@onready var god_icon_preview: TextureRect = $Page/VBox/Scroll/Columns/Side/YouCard/VBox/NameRow/GodIconPreview
@onready var start_game_button = $Page/VBox/BottomBar/StartGameButton
@onready var start_caption: Label = $Page/VBox/BottomBar/StartCaption
@onready var options_button = $Page/VBox/Scroll/Columns/Side/RunCard/VBox/Row/OptionsButton
@onready var leave_button = $Page/VBox/BottomBar/LeaveButton
@onready var status_label = $Page/VBox/BottomBar/StatusLabel
@onready var lobby_id_box: HBoxContainer = $Page/VBox/Header/LobbyIdBox
@onready var lobby_id_label = $Page/VBox/Header/LobbyIdBox/LobbyIdLabel
@onready var copy_button: Button = $Page/VBox/Header/LobbyIdBox/CopyButton
@onready var ips_line: LineEdit = $Page/VBox/IpsLine
# The run setup: everyone reads it in one line in "The run", and OPTIONS opens
# the full panel (editable for the host, read-only for clients).
@onready var run_summary_label: Label = $Page/VBox/Scroll/Columns/Side/RunCard/VBox/Row/RunSummaryLabel
@onready var build_card: PanelContainer = $Page/VBox/Scroll/Columns/Side/BuildCard
@onready var build_slots: HBoxContainer = $Page/VBox/Scroll/Columns/Side/BuildCard/VBox/Slots
@onready var lobby_options = $LobbyOptions

var connected_players = {}
var is_host = false
# The icon picker, one toggle button per god with an icon (metadata "god_id").
var god_icon_buttons: Array[Button] = []
# CUSTOM BUILD: one icon box per slot (E, Q) and the all-skills popup it opens.
# Each player edits only its own pair - Network.choose_custom_build reads the
# sender, never an argument - so the card never shows anyone else's picks.
var _build_buttons: Array[Button] = []
var _build_names: Array[Label] = []
var _picker: Control
var _picker_title: Label
var _picker_grid: GridContainer

func _ready():
	# Connect button signals
	start_game_button.pressed.connect(_on_start_game_pressed)
	options_button.pressed.connect(_on_options_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	change_name_button.pressed.connect(_on_change_name_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	copy_button.pressed.connect(_on_copy_pressed)

	# Connect to network signals
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	Network.player_list_updated.connect(_on_player_list_updated)
	Network.player_god_icon_changed.connect(_on_player_god_icon_changed)
	_populate_god_icons()
	_setup_build_card()
	Network.run_settings_changed.connect(_on_run_settings_changed)

	# Check if we're the host
	is_host = multiplayer.is_server()

	if is_host:
		status_label.text = "You are the host. Waiting for players..."
		# Show the lobby ID so friends can join directly - no IP/port needed
		lobby_id_label.text = Network.lobby_id if Network.lobby_id != "" else "----"
		lobby_id_box.visible = true
		# ...and the IPs, for friends on a VPN where the broadcast never reaches them
		ips_line.text = HostAddress.ips_line(IP.get_local_addresses(), Network.host_port())
		ips_line.add_theme_color_override("font_uneditable_color", UITokens.MUTED)
		ips_line.visible = ips_line.text != ""
		# Prefill name with the host's random name
		var my_id = multiplayer.get_unique_id()
		if my_id in Network.players:
			name_input.text = str(Network.players[my_id])
	else:
		status_label.text = "Connected to host. Waiting for game to start..."
		start_game_button.visible = false
		# Only the host shares the lobby ID
		lobby_id_box.visible = false

	# Request current player list from server
	if is_host:
		Network.broadcast_player_list()
		connected_players = Network.players.duplicate()
		_update_player_list()
		var my_id = multiplayer.get_unique_id()
		if my_id in connected_players:
			name_input.text = str(connected_players[my_id])
	else:
		Network.rpc_id(1, "request_player_list")

	_update_player_list()
	_refresh_run_summary()
	_refresh_build_card()
	_update_start_button()
	for button in god_icon_buttons:
		if button.button_pressed:
			button.grab_focus()


func _on_run_settings_changed(_settings: Dictionary) -> void:
	_refresh_run_summary()
	_refresh_build_card()
	_update_start_button()


func _refresh_run_summary() -> void:
	run_summary_label.text = Network.run_settings.summary()


# START needs enough players AND a legal setup (no god twice in a row in a
# CUSTOM order) - the panel shows the warning, this keeps the button honest and
# its caption says which of the two is missing.
func _update_start_button() -> void:
	if not is_host:
		start_caption.text = "The host starts the game"
		start_caption.remove_theme_color_override("font_color")
		return
	var reason := ""
	if connected_players.size() < Network.MIN_PLAYERS_TO_START:
		reason = "Need %d+ players" % Network.MIN_PLAYERS_TO_START
	else:
		var problems: Array[String] = Network.run_settings.problems()
		if not problems.is_empty():
			reason = problems[0]
	start_game_button.disabled = not reason.is_empty()
	start_game_button.tooltip_text = reason
	start_caption.text = reason if not reason.is_empty() else "Everyone ready?"
	if reason.is_empty():
		start_caption.add_theme_color_override("font_color", UITokens.JADE)
	else:
		start_caption.add_theme_color_override("font_color", UITokens.readable_on_dark(UITokens.EMBER, UITokens.NIGHT_900))


func _on_options_pressed() -> void:
	if lobby_options.visible:
		lobby_options.close()
	else:
		lobby_options.open(is_host)
		UITokens.reveal(lobby_options)


func _on_start_game_pressed():
	if is_host and connected_players.size() >= Network.MIN_PLAYERS_TO_START and Network.run_settings.problems().is_empty():
		Network.start_game()

func _on_leave_pressed():
	if is_host:
		Network.stop_host()
	else:
		Network.leave_host()

	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# Lobby ID -> clipboard, with a moment of "COPIED" as the feedback.
func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(Network.lobby_id)
	copy_button.text = "COPIED"
	get_tree().create_timer(COPIED_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(copy_button):
			copy_button.text = "COPY")


# Esc means back - but here "back" closes the lobby for everyone (host) or drops
# the player out of it, so Esc only takes focus to LEAVE; Enter confirms. An open
# popup (OPTIONS, the build picker) handles Esc first - it is the nearer "back".
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _picker != null and _picker.visible:
		get_viewport().set_input_as_handled()
		_close_build_picker()
		return
	if not lobby_options.visible:
		get_viewport().set_input_as_handled()
		leave_button.grab_focus()

func _on_player_joined(player_id: int):
	print("Player joined lobby: ", player_id)
	_update_player_list()

func _on_player_left(player_id: int):
	print("Player left lobby: ", player_id)
	connected_players.erase(player_id)
	_update_player_list()

func _on_change_name_pressed():
	_change_name()

func _on_name_submitted(_text: String):
	_change_name()

func _change_name():
	var new_name = name_input.text.strip_edges()
	if new_name.is_empty():
		status_label.text = "Please enter a valid name"
		return

	var my_id = multiplayer.get_unique_id()
	if is_host:
		Network.request_name_change(my_id, new_name)
	else:
		Network.rpc_id(1, "request_name_change", my_id, new_name)
	status_label.text = "Changing name to: " + new_name

func _on_player_list_updated(players: Dictionary):
	connected_players = players.duplicate()
	_update_player_list()
	_refresh_build_card()

func _update_player_list():
	# Clear existing slots immediately (not deferred) to prevent overlap
	for child in player_list_vbox.get_children():
		player_list_vbox.remove_child(child)
		child.queue_free()

	# One slot per seat at the table: the players in join order, then the empty seats.
	var ids: Array = connected_players.keys()
	for seat in range(Network.MAX_PLAYERS):
		if seat < ids.size():
			player_list_vbox.add_child(_player_slot(ids[seat]))
		else:
			player_list_vbox.add_child(_empty_slot())
	roster_label.text = "MORTALS  %d/%d" % [connected_players.size(), Network.MAX_PLAYERS]

	# Update start game button state
	if is_host:
		_update_start_button()


# A filled seat: [icon in its god's accent frame] name ............ [HOST]
func _player_slot(player_id) -> PanelContainer:
	var player_god := Gods.by_id(StringName(str(Network.player_icons.get(player_id, &"mayari"))))
	var accent := UITokens.god_accent(player_god)
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"PanelRow"
	slot.add_theme_stylebox_override("panel", UITokens.accent_box(slot.get_theme_stylebox("panel", &"PanelRow"), accent))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UITokens.SPACE_8)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"PanelInset"
	var frame_box: StyleBox = UITokens.accent_box(frame.get_theme_stylebox("panel", &"PanelInset"), accent)
	frame_box.set_content_margin_all(UITokens.SPACE_4)
	frame.add_theme_stylebox_override("panel", frame_box)
	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.custom_minimum_size = SLOT_ICON
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if player_god != null:
		icon_rect.texture = player_god.icon
	frame.add_child(icon_rect)
	hbox.add_child(frame)

	var bandana := BandanaSwatch.mark(int(Network.player_bandanas.get(player_id, 0)))
	bandana.name = "Bandana"
	hbox.add_child(bandana)

	var label = Label.new()
	label.text = str(connected_players[player_id])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(label)

	# Add host indicator
	if int(player_id) == 1:
		var plate := PanelContainer.new()
		plate.theme_type_variation = &"Nameplate"
		plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var host_label := Label.new()
		host_label.text = "HOST"
		host_label.add_theme_color_override("font_color", UITokens.GOLD)
		plate.add_child(host_label)
		hbox.add_child(plate)
	if int(player_id) == multiplayer.get_unique_id():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", UITokens.SPACE_8)
		column.add_child(hbox)
		column.add_child(_bandana_picker(int(player_id)))
		slot.add_child(column)
	else:
		slot.add_child(hbox)
	return slot


# YOUR bandana: one swatch per colour. A colour another player holds is locked
# (greyed, a padlock, tooltip says who); the one you wear has the gold frame.
func _bandana_picker(player_id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "BandanaPicker"
	row.add_theme_constant_override("separation", UITokens.SPACE_8)
	var caption := Label.new()
	caption.text = "BANDANA"
	caption.theme_type_variation = &"CaptionLabel"
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	var mine := int(Network.player_bandanas.get(player_id, 0))
	for index in range(UITokens.BANDANA_COLORS.size()):
		var holder := 0
		for other in Network.player_bandanas.keys():
			if int(Network.player_bandanas[other]) == index:
				holder = int(other)
		var taken := holder != 0 and holder != player_id
		var swatch := BandanaSwatch.new()
		swatch.name = "Color%d" % index
		swatch.setup(index, taken, index == mine, str(connected_players.get(holder, "another player")))
		swatch.focus_mode = Control.FOCUS_ALL
		swatch.pressed.connect(_on_bandana_picked.bind(index))
		row.add_child(swatch)
	return row


func _on_bandana_picked(index: int) -> void:
	Network.choose_bandana_color(index)


func _empty_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"PanelEmpty"
	slot.custom_minimum_size.y = SLOT_ICON.y + 24
	var label := Label.new()
	label.text = EMPTY_TEXT
	label.theme_type_variation = &"MutedLabel"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(label)
	return slot


# The icon picker: one toggle per god that has an icon, exactly one pressed.
func _populate_god_icons() -> void:
	for child in god_icon_row.get_children():
		god_icon_row.remove_child(child)
		child.queue_free()
	god_icon_buttons.clear()
	var group := ButtonGroup.new()
	var selected_id := Network.my_god_icon_id
	for god in Gods.all():
		if god.icon == null:
			continue
		var button := Button.new()
		button.theme_type_variation = &"IconButton"
		button.custom_minimum_size = UITokens.BUTTON_ICON_LARGE
		button.icon = god.icon
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = "%s, %s" % [god.display_name, god.epithet]
		button.set_meta("god_id", god.id)
		button.button_pressed = god.id == selected_id
		button.pressed.connect(_on_god_icon_selected.bind(god_icon_buttons.size()))
		god_icon_row.add_child(button)
		god_icon_buttons.append(button)
	if god_icon_buttons.is_empty():
		return
	_show_god_icon(selected_id)


func _on_god_icon_selected(index: int) -> void:
	var god_id := StringName(str(god_icon_buttons[index].get_meta("god_id")))
	god_icon_buttons[index].set_pressed_no_signal(true)
	_show_god_icon(god_id)
	Network.choose_player_god_icon(god_id)


func _show_god_icon(god_id: StringName) -> void:
	var god := Gods.by_id(god_id)
	if god != null:
		god_icon_preview.texture = god.icon


func _on_player_god_icon_changed(peer_id: int, god_id: StringName) -> void:
	if peer_id == multiplayer.get_unique_id():
		_show_god_icon(god_id)
		for button in god_icon_buttons:
			if StringName(str(button.get_meta("god_id"))) == god_id:
				button.set_pressed_no_signal(true)
				break
	_update_player_list()


# ============================================
# CUSTOM BUILD
# ============================================
# The card under THE RUN, shown only while the starter mode is CUSTOM: two icon
# boxes, E and Q. It always reads THIS player's pair - builds are not shared, and
# Network.choose_custom_build can only ever change the sender's own - so picking
# an icon here never touches anyone else's hands. An empty (or never picked)
# side is Mayari's own skill, the same fallback the host grants at START.

const BUILD_SLOT_SIZE := Vector2(72, 72)
const PICKER_CARD_COLUMNS := 3


func _setup_build_card() -> void:
	for slot in [GodFavor.Slot.E, GodFavor.Slot.Q]:
		var column := VBoxContainer.new()
		column.name = "Slot%s" % ("E" if slot == GodFavor.Slot.E else "Q")
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", UITokens.SPACE_4)
		var caption := Label.new()
		caption.text = "E" if slot == GodFavor.Slot.E else "Q"
		caption.theme_type_variation = &"CaptionLabel"
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
		var button := Button.new()
		button.name = "Skill"
		button.theme_type_variation = &"IconButton"
		button.custom_minimum_size = BUILD_SLOT_SIZE
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
		button.pressed.connect(_open_build_picker.bind(slot))
		column.add_child(button)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.theme_type_variation = &"MutedLabel"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size.x = 120
		column.add_child(name_label)
		build_slots.add_child(column)
		_build_buttons.append(button)
		_build_names.append(name_label)
	_build_picker()


# The all-skills popup: a dim backdrop under a card of every favor this slot can
# deal (RunSettings.starter_pool - an implemented god's, asking nothing first).
# The current pick is gold; pressing any card sends that pick to the host.
func _build_picker() -> void:
	_picker = Control.new()
	_picker.name = "BuildPicker"
	_picker.visible = false
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_picker)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(UITokens.NIGHT_900, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PanelCard"
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITokens.SPACE_8)
	panel.add_child(vbox)
	_picker_title = Label.new()
	_picker_title.theme_type_variation = &"HeadingLabel"
	vbox.add_child(_picker_title)
	var hint := Label.new()
	hint.theme_type_variation = &"MutedLabel"
	hint.text = "Every skill a mortal may open with. Yours is gold."
	vbox.add_child(hint)
	_picker_grid = GridContainer.new()
	_picker_grid.name = "Skills"
	_picker_grid.columns = PICKER_CARD_COLUMNS
	_picker_grid.add_theme_constant_override("h_separation", UITokens.SPACE_8)
	_picker_grid.add_theme_constant_override("v_separation", UITokens.SPACE_8)
	vbox.add_child(_picker_grid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(row)
	var cancel := Button.new()
	cancel.theme_type_variation = &"SmallButton"
	cancel.text = "CANCEL"
	cancel.pressed.connect(_close_build_picker)
	row.add_child(cancel)


func _open_build_picker(slot: int) -> void:
	var pair := Network.my_build_favors()
	var current: GodFavor = pair[0] if slot == GodFavor.Slot.E else pair[1]
	_picker_title.text = "YOUR %s" % ("E" if slot == GodFavor.Slot.E else "Q")
	for child in _picker_grid.get_children():
		_picker_grid.remove_child(child)
		child.queue_free()
	for favor in RunSettings.starter_pool(slot):
		var god := Gods.by_id(favor.god_id)
		var card := Button.new()
		card.custom_minimum_size = Vector2(176, 88)
		card.icon = favor.icon
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.text = "%s\n%s" % [god.display_name.capitalize() if god != null else str(favor.god_id),
			favor.display_name]
		card.tooltip_text = "%s - %s\n%s" % [god.display_name if god != null else str(favor.god_id),
			favor.display_name, favor.description]
		if current != null and current.id == favor.id:
			card.add_theme_color_override("font_color", UITokens.GOLD)
			card.tooltip_text += "\n(yours)"
		card.pressed.connect(_pick_build.bind(slot, favor.id))
		_picker_grid.add_child(card)
	_picker.visible = true
	UITokens.reveal(_picker)


func _pick_build(slot: int, favor_id: StringName) -> void:
	Network.choose_custom_build(slot, favor_id)
	_close_build_picker()


func _close_build_picker() -> void:
	if _picker != null:
		_picker.visible = false


# Repaint the two boxes from this machine's own build (and hide the card outside
# a CUSTOM run). Called whenever the setup or the roster changes - a pick comes
# back from the host with the roster, so this is the one place the boxes learn it.
func _refresh_build_card() -> void:
	var custom := Network.run_settings.starter_mode == RunSettings.STARTER_CUSTOM
	build_card.visible = custom
	if not custom:
		_close_build_picker()
		return
	var pair := Network.my_build_favors()
	for index in range(_build_buttons.size()):
		var favor: GodFavor = pair[index] if index < pair.size() else null
		var button := _build_buttons[index]
		var name_label := _build_names[index]
		if favor == null:
			button.icon = null
			button.tooltip_text = "Click to pick a skill."
			name_label.text = "-"
			continue
		var god := Gods.by_id(favor.god_id)
		button.icon = favor.icon
		button.tooltip_text = "%s - %s\n%s\nClick to change." % [
			god.display_name if god != null else str(favor.god_id), favor.display_name, favor.description]
		name_label.text = favor.display_name
