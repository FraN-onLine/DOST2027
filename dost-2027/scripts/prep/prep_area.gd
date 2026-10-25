class_name PrepArea
extends Arena

# THE PREPARATION AREA - PAHINGA ("rest"), between two trials. (scripts/prep +
# scenes/prep)
#
# After every trial but the last, the Game shell opens this instead of the next
# arena: every mortal lands on one small shared field for prep_time seconds (the
# lobby's PREP TIME, RunSettings.prep_time, handed over by the shell), around a
# campfire, between two things to do -
#   * the ALTAR of the god who just hosted (god_id): F opens the God's Due menu
#     for that god anywhere on the field. It only SELLS: every card is a blessing
#     (a boon) of that god for boon_cost FAVOR, whatever God's Due vouchers or free
#     grants the mortal holds - those are never spent here and wait for the next
#     trial, where F spends them as usual. max_boon_purchases per mortal per rest
#     (apart from the Pamana - one of each is allowed); then the cards lock and the
#     altar's hint says the blessing was bought. The host checks every purchase (try_buy_boon ->
#     GodMatch.buy_boon: this god's, eligible, not held, affordable) and pays it
#     with spend_favor - never a loss; a skill takes its slot in place of the old
#     one (bestow_favor), which its card warns about. Everyone hears
#     "<name> bought <favor>";
#   * the TINDAHAN stall: walk up to it and LEFT CLICK for the shop
#     (UI/GodsArena/tindahan_menu.tscn). The host rolls up to offer_count
#     Pamana for each mortal (Game.pamana_rng, one generator per run), only the
#     ones that can help them, and sends each client ONLY its own. Each mortal
#     buys at most max_purchases; the host checks every purchase and pays it
#     through GodMatch.buy_pamana (spend_favor - never a loss). Everyone hears
#     "<name> bought <item>"; only the buyer sees what it did not take.
# The timer pill reads PAHINGA, a banner under it names the next trial, and R
# (ready_up) says you are done: the rest ends when every connected mortal is
# ready (a mortal who leaves counts as ready) or the time runs out.
#
# WHY IT EXTENDS ARENA: it gets the mortal, the ghosts of the other players, the
# position sync, the God's Due menu and every RPC the base already speaks - the
# READY is the base's dialogue handshake under the token "<prefix>_ready", so the
# host's release reaches every screen the way a dialogue's does. What it turns
# off: the intro dialogue, the countdown, the clock that ends a trial, the
# results, E / Q and the dash (the phase stays INTRO, which allows none of them),
# and every screen effect of a loss (_on_sun_favor_changed).
#
# NO FAVOR MOVES HERE EXCEPT PURCHASES: begin_trial / end_trial are never called
# (First Light and Favorable Outcome are not paid twice), rules.trial_active stays
# false (GodMatch ticks no Harvest Pair rule and no Pamana window without it), the
# solo rivals are not simulated (simulate_rivals = false in the scene) and The
# Great's ticker belongs to the trial clock this scene never runs.

signal prep_closed

const READY_MARK := " √"  # on a ready player's name tag (Minecraftia has no check mark)
const ALTAR_ICON_SIZE := 48.0  # the god on the altar, whatever size its icon is drawn at

@export_category("Preparation Area")
@export var prep_time := 20.0       # seconds of rest (the shell sets the lobby's; this is the standalone fallback)
@export var max_purchases := 1      # Pamana each mortal may buy here (the anti-snowball rule)
@export var boon_cost := GodMatch.BOON_COST  # FAVOR for a blessing at the altar (vouchers are kept)
@export var max_boon_purchases := 1  # boons each mortal may buy here, apart from the Pamana
@export var offer_count := 3        # Pamana on each mortal's shelf
@export var stall_reach := 90.0     # how close to the stall LEFT CLICK opens the Tindahan

@onready var altar_icon: Sprite2D = $Camp/Altar/GodIcon
@onready var altar_name: Label = $Camp/Altar/Name
@onready var altar_hint: Label = $Camp/Altar/Hint
@onready var stall: Node2D = $Camp/Stall
@onready var stall_hint: Label = $Camp/Stall/Hint
@onready var next_label: Label = $PrepHud/Next
@onready var ready_label: Label = get_node(BAND_STATE + "Ready")
@onready var shop: Control = $PrepHud/Tindahan
@onready var fire_glow: Sprite2D = $Camp/Campfire/Glow
@onready var fire_light: PointLight2D = $Camp/Campfire/Light

var _flicker := 1.0                     # the campfire's glow, wobbling 0.9 - 1.1 (visual only, not synced)
var rng: RandomNumberGenerator = null   # the run's own, handed over by the Game shell
var _time_left := 0.0
var _closed := false
var _offers: Dictionary = {}            # host: mortal id -> Array[StringName]
var _my_offers: Array[StringName] = []  # a client: its own offers, as the host sent them
var _bought: Dictionary = {}            # mortal id -> Array[StringName] (host decides, the tick mirrors)
var _boons: Dictionary = {}             # mortal id -> Array[StringName] boons bought here (the same)
var _ready_ids: Array = []              # who said READY (host: Network; client: the tick)
var _tags: Dictionary = {}              # mortal id -> the name tag last drawn


# The prep area is not a trial: nobody falls from the sky into it.
func drop_applies() -> bool:
	return false


# --- OPENING ---------------------------------------------------------------------

# The base calls this at the end of _ready: no dialogue, no countdown - the rest
# begins at once, on the field, with the clock at prep_time.
func _start_intro() -> void:
	_phase = Phase.INTRO
	player.set_lock(false)
	_time_left = prep_time
	_trial_time = prep_time
	# The READY handshake's token: set on every screen now, so the host's release
	# (ready or out of time) reaches this screen even if it never pressed READY.
	_dialogue_wait_id = _dialogue_token("ready")
	shop.pamana_chosen.connect(_on_pamana_chosen)
	due_menu.boon_chosen.connect(_on_boon_chosen)
	# The shell hides the event line in a trial; here the purchases read on it, just
	# above READY, and the banner sits under the NEXT banner instead of on it.
	hud.event_label.visible = true
	hud.event_label.offset_left = Arena.UI_STRIP_WIDTH + 4.0
	hud.event_label.offset_top = -80.0
	hud.event_label.offset_bottom = -56.0
	hud.banner_label.offset_top = 96.0
	hud.banner_label.offset_bottom = 144.0
	hud.log_event("Rest. The next trial is coming.", UITokens.MUTED)
	# The run's FAVOR arrives with the shell's snapshot: not a gain, no popup.
	popups_enabled = false
	_paint_camp()
	trial_time_changed.emit(_time_left)


# The Game shell calls this once the run's snapshot is in the match: only now do
# the mortals hold the favors the offers are filtered by.
func open_prep() -> void:
	popups_enabled = true
	if _authority:
		for id in _shoppers():
			_send_offers(id)
	elif _my_offers.is_empty() and _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_prep_offers")


func _paint_camp() -> void:
	if god != null and god.icon != null:
		altar_icon.texture = god.icon
		altar_icon.scale = Vector2.ONE * ALTAR_ICON_SIZE / maxf(1.0, float(god.icon.get_width()))
	if god != null:
		altar_name.text = "ALTAR OF %s" % god.display_name
		altar_name.add_theme_color_override("font_color", UITokens.god_text(god))
	_paint_altar_hint()
	var next := Gods.by_id(next_god_id) if next_god_id != &"" else null
	next_label.visible = next != null
	if next != null:
		next_label.text = "NEXT: %s - %s" % [next.display_name.to_upper(), next.game_name.to_upper()]
		next_label.add_theme_color_override("font_color", UITokens.god_text(next))
	hint_label.text = "[WASD] WALK   %s BLESSING   %s READY   %s TINDAHAN" % [
		key_cap(&"due_menu"), key_cap(&"ready_up"), key_cap(&"attack")]


# The follow camera's edge arrows: the altar and the stall, the two things to do.
func edge_targets() -> Array:
	return [$Camp/Altar, stall]


# --- THE TINDAHAN: offers and purchases (the host decides) ----------------------------

# Who shops here: every connected mortal, or only us solo (simulated rivals don't).
func _shoppers() -> Array:
	if _networked:
		return rules.mortals.keys()
	return [_my_id]


# A mortal's offers, rolled the first time they are asked for and never again -
# a reopened panel or a repeated request always gets the same shelf.
func offers_for(mortal_id: int) -> Array[StringName]:
	if not _offers.has(mortal_id):
		_offers[mortal_id] = _roll_offers(mortal_id)
	return _offers[mortal_id]


# Up to offer_count different Pamana, only those that can help this mortal.
func _roll_offers(mortal_id: int) -> Array[StringName]:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var pool: Array[StringName] = []
	for item in Pamanas.all():
		if rules.pamana_useful(item, mortal_id):
			pool.append(item.id)
	# Fisher-Yates with the run's generator (Array.shuffle would use the global one).
	for index in range(pool.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held := pool[index]
		pool[index] = pool[swap]
		pool[swap] = held
	return pool.slice(0, offer_count)


func _send_offers(mortal_id: int) -> void:
	var offers := offers_for(mortal_id)
	if mortal_id == _my_id or _net == null:
		return
	var ids: Array = []
	for id in offers:
		ids.append(str(id))
	_net.send_prep_offers(mortal_id, ids)


func _on_prep_offers_requested(peer_id: int) -> void:
	if _authority and not _closed:
		_send_offers(peer_id)


func _on_prep_offers_received(offers: Array) -> void:
	_my_offers.clear()
	for id in offers:
		_my_offers.append(StringName(str(id)))


func my_offers() -> Array[StringName]:
	return offers_for(_my_id) if _authority else _my_offers


func bought_by(mortal_id: int) -> Array:
	return _bought.get(mortal_id, [])


# Host: `mortal_id` buys `pamana_id`. Refused unless it is one of their offers,
# they have a purchase left and they can pay. Returns true when it went through.
func try_purchase(mortal_id: int, pamana_id: StringName) -> bool:
	if not _authority or _closed:
		return false
	var item := Pamanas.by_id(pamana_id)
	if item == null or not offers_for(mortal_id).has(pamana_id):
		return false
	var bought := bought_by(mortal_id)
	if bought.size() >= max_purchases or bought.has(pamana_id):
		return false
	if not rules.buy_pamana(item, mortal_id):
		return false
	bought = bought.duplicate()
	bought.append(pamana_id)
	_bought[mortal_id] = bought
	var line := "%s bought %s" % [mortal_label(mortal_id), item.display_name]
	_show_banner(line, UICards.pamana_edge(item), 2.0)
	_log(line, UICards.pamana_edge(item))
	_publish_god_state()
	return true


func _on_prep_purchase_requested(peer_id: int, pamana_id: String) -> void:
	try_purchase(peer_id, StringName(pamana_id))


func _on_pamana_chosen(item: Pamana) -> void:
	if _authority:
		try_purchase(_my_id, item.id)
	elif _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_prep_purchase", str(item.id))


# --- THE ALTAR'S BOONS (the host decides) --------------------------------------------

func boons_bought_by(mortal_id: int) -> Array:
	return _boons.get(mortal_id, [])


func boons_left(mortal_id: int) -> int:
	return maxi(0, max_boon_purchases - boons_bought_by(mortal_id).size())


# Host: `mortal_id` buys the boon `favor_id` for FAVOR - never with a voucher, which
# stays for the next trial. Refused unless they have a boon left here and
# GodMatch.buy_boon agrees (this god's favor, eligible, not held, affordable).
# Returns true when they got it.
func try_buy_boon(mortal_id: int, favor_id: StringName) -> bool:
	if not _authority or _closed or god == null:
		return false
	var favor := god.get_favor(favor_id)
	var mortal := rules.mortal(mortal_id)
	if favor == null or mortal == null:
		return false
	if boons_left(mortal_id) <= 0 or not rules.buy_boon(favor, mortal_id, boon_cost):
		return false
	var bought := boons_bought_by(mortal_id).duplicate()
	bought.append(favor_id)
	_boons[mortal_id] = bought
	var line := "%s bought %s" % [mortal_label(mortal_id), favor.display_name]
	_show_banner(line, favor.color, 2.0)
	_log(line, favor.color)
	_publish_god_state()
	return true


func _on_boon_purchase_requested(peer_id: int, favor_id: String) -> void:
	try_buy_boon(peer_id, StringName(favor_id))


func _on_boon_chosen(favor: GodFavor) -> void:
	if _authority:
		try_buy_boon(_my_id, favor.id)
	elif _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_boon_purchase", str(favor.id))


# The base's God's Due menu as the altar's shop: every card for boon_cost FAVOR.
func _toggle_due_menu() -> void:
	if due_menu.is_open():
		due_menu.close()
		return
	due_menu.open(god, rules, _free_grants, not _authority, boon_cost, boons_left(_my_id))


func _near_stall() -> bool:
	return player.global_position.distance_to(stall.global_position) <= stall_reach


func open_shop() -> void:
	if _closed or due_menu.is_open():
		return
	var items: Array[Pamana] = []
	for id in my_offers():
		var item := Pamanas.by_id(id)
		if item != null:
			items.append(item)
	var mine := bought_by(_my_id)
	shop.open(items, local_favor(), mine, mine.size() >= max_purchases)


# --- READY / CLOSING ---------------------------------------------------------------

func _ready_up() -> void:
	if _closed or (_dialogue_waiting and _dialogue_wait_id == _dialogue_token("ready")):
		return
	if not _ready_ids.has(_my_id):
		_ready_ids.append(_my_id)
	_wait_for_dialogue("ready")  # solo: closes at once; networked: tells the host


func is_ready(mortal_id: int) -> bool:
	return _ready_ids.has(mortal_id)


# How many of the CONNECTED mortals are ready, out of how many (a mortal who left
# is not waited for).
func ready_count() -> Vector2i:
	if not _networked or _net == null:
		return Vector2i(1 if is_ready(_my_id) else 0, 1)
	var ready := 0
	for id in _net.players.keys():
		if is_ready(int(id)):
			ready += 1
	return Vector2i(ready, _net.players.size())


func _all_ready() -> bool:
	var count := ready_count()
	return count.y > 0 and count.x >= count.y


# Host: end the rest for everyone (all ready, or out of time).
func _release_prep() -> void:
	if _closed:
		return
	if _networked and _net != null:
		_dialogue_wait_id = _dialogue_token("ready")
		_net.release_dialogue(_dialogue_wait_id)  # comes back as dialogue_released
	else:
		_close_prep()


# The base's dialogue handshake just released the READY token.
func _continue_dialogue() -> void:
	_close_prep()


func _close_prep() -> void:
	if _closed:
		return
	_closed = true
	shop.close()
	if due_menu.is_open():
		due_menu.close()
	player.set_lock(true)
	if _authority:
		_publish_god_state()  # the last word before the next trial reads it
	prep_closed.emit()


func is_closed() -> bool:
	return _closed


# --- FRAME -----------------------------------------------------------------------------
# Not the base's frame: no trial clock, no countdown, no rules tick. Only the rest's
# own clock, the network plumbing the base offers, and this screen's HUD.

func _process(delta: float) -> void:
	_tick_fire(delta)
	_tick_field_dim()
	_tick_band()
	if _authority:
		if not _closed:
			_time_left = maxf(0.0, _time_left - delta)
			_trial_time = _time_left
			trial_time_changed.emit(_time_left)
			hud.set_time_left(_time_left)
			if _networked and _net != null:
				for id in _net.dialogue_finished_ids(_dialogue_token("ready")):
					if not _ready_ids.has(int(id)):
						_ready_ids.append(int(id))
			if _time_left <= 0.0 or _all_ready():
				_release_prep()
		if _networked:
			_publish_net_tick(delta)
	else:
		_time_left = _trial_time
		_client_tick(delta)
	_flush_favor_popups(delta)
	_move_ghosts(delta)
	_refresh_prep_hud()


# The campfire's glow breathes: its scale and alpha chase a new random value in
# 0.9 - 1.1 (0.98 - 1.02 with Reduce Flashing on) a few times a second.
func _tick_fire(delta: float) -> void:
	var spread := 0.02 if reduce_flashing() else 0.1
	_flicker = lerpf(_flicker, randf_range(1.0 - spread, 1.0 + spread), minf(1.0, delta * 8.0))
	fire_glow.scale = Vector2.ONE * 1.09375 * _flicker
	fire_glow.modulate.a = _flicker
	fire_light.energy = 0.35 * _flicker


# The altar says what F does there - until this mortal's blessing is bought.
func _paint_altar_hint() -> void:
	if boons_left(_my_id) > 0:
		altar_hint.text = "%s - BUY A BLESSING (%d FAVOR)" % [UITokens.key_text(&"due_menu"), boon_cost]
	else:
		altar_hint.text = "BLESSING BOUGHT"


func _refresh_prep_hud() -> void:
	_paint_altar_hint()
	var near := _near_stall()
	stall_hint.visible = near and not shop.is_open() and not _closed
	if shop.is_open():
		if not near:
			shop.close()
		else:
			var mine := bought_by(_my_id)
			shop.refresh(local_favor(), mine, mine.size() >= max_purchases)
	var count := ready_count()
	ready_label.text = "READY %d/%d" % [count.x, count.y]
	ready_label.add_theme_color_override("font_color", UITokens.JADE if is_ready(_my_id) else UITokens.IVORY)
	_tag(_my_id, player)
	for id in _ghosts.keys():
		if is_instance_valid(_ghosts[id]):
			_tag(int(id), _ghosts[id])


func _tag(mortal_id: int, body: ArenaMortal) -> void:
	var text := mortal_label(mortal_id) + (READY_MARK if is_ready(mortal_id) else "")
	if _tags.get(mortal_id, "") == text:
		return
	_tags[mortal_id] = text
	body.set_display_name(text, UITokens.JADE if is_ready(mortal_id) else tag_color(mortal_id))


# What every client needs from the host's rest besides the base's tick: who is
# ready, and who bought what (so a buyer's card reads BINILI, and the altar's
# cards lock once their boons are bought).
func arena_tick_fields() -> Dictionary:
	return {"ready": _ready_ids.duplicate(), "bought": _ids_out(_bought), "boons": _ids_out(_boons)}


func arena_read_tick(state: Dictionary) -> void:
	_ready_ids.clear()
	for id in state.get("ready", []):
		_ready_ids.append(int(id))
	_bought = _ids_in(state.get("bought", {}))
	_boons = _ids_in(state.get("boons", {}))


# mortal id -> Array[StringName], as it travels (string keys and ids) and back.
static func _ids_out(per_mortal: Dictionary) -> Dictionary:
	var out := {}
	for id in per_mortal.keys():
		out[str(id)] = (per_mortal[id] as Array).map(func(p: StringName) -> String: return str(p))
	return out


static func _ids_in(per_mortal: Dictionary) -> Dictionary:
	var out := {}
	for key in per_mortal.keys():
		var items: Array = []
		for id in per_mortal[key]:
			items.append(StringName(str(id)))
		out[int(key)] = items
	return out


# --- INPUT -------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _closed or not (event is InputEventMouseButton) or not event.is_action_pressed("attack"):
		return
	if hud.click_skill_popup(event.position):  # a click that closes the skill popup is not a click at the stall
		get_viewport().set_input_as_handled()
		return
	if shop.is_open() or due_menu.is_open() or not _near_stall():
		return
	open_shop()
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


# Only what the rest allows: F (the God's Due menu), R (ready) and Esc. No E / Q,
# no dash, and the base's R-to-restart never reaches here.
func _unhandled_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport == null or _closed:
		return
	if event.is_action_pressed("due_menu"):
		viewport.set_input_as_handled()
		shop.close()
		_toggle_due_menu()
	elif event.is_action_pressed("ready_up"):
		viewport.set_input_as_handled()
		_ready_up()
	elif event.is_action_pressed("ui_cancel") and due_menu.is_open():
		viewport.set_input_as_handled()
		due_menu.close()


# --- WHAT THE REST LEAVES OUT ------------------------------------------------------------

# A loss's screen effects (Sun Patches, The Victor) belong to a trial.
func _on_sun_favor_changed(_player_id: int, _delta: int) -> void:
	pass


func _connect_network() -> void:
	super._connect_network()
	if _net == null or not _networked:
		return
	if _authority:
		_net.connect("prep_offers_requested", _on_prep_offers_requested)
		_net.connect("prep_purchase_requested", _on_prep_purchase_requested)
		_net.connect("boon_purchase_requested", _on_boon_purchase_requested)
	else:
		_net.connect("prep_offers_received", _on_prep_offers_received)
