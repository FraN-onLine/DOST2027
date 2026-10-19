extends SceneTree

# Generator for the Pamana (heirloom) resources: turns the definitions below into
# one Pamana .tres per item under res://resources/pamana/, like
# tools/build_gods.gd does for the gods. Edit an item here and run this again,
# or tune the .tres in the editor - both end up in the same files.
# Run: godot --headless --path <project> -s res://tools/build_pamana.gd

const OUT_DIR := "res://resources/pamana"
const ICON := "res://icon.svg"  # placeholder art until the real icons arrive

const ITEMS := [
	{
		"id": &"manunggul_jar", "name": "Manunggul Jar", "cost": 200,
		"timing": Pamana.Timing.WHOLE_TRIAL, "needs": Pamana.Needs.NOTHING,
		"effect": "Next trial: 25% of the FAVOR you lose comes back to you when the trial ends.",
		"params": {"return_share": 0.25},
		"era": "c. 890–710 BC", "origin": "Manunggul Cave, Tabon Caves, Palawan",
		"history": "A burial jar from the Late Neolithic, found by National Museum archaeologists in the 1960s. On its lid, two souls sail a boat of the dead toward the afterlife: early Filipinos saw death as a journey, not an end. It is a National Treasure, kept at the National Museum in Manila.",
		"flavor": "What is lost is only carried across.",
		"color": Color("#B8704F"),  # earthen clay
	},
	{
		"id": &"torn_cedulas", "name": "Torn Cedulas", "cost": 100,
		"timing": Pamana.Timing.FIRST_WINDOW, "needs": Pamana.Needs.E_SKILL,
		"effect": "Next trial: your E skill's cooldown is 20% shorter for the first 30 seconds.",
		"params": {"cooldown_multiplier": 0.8},
		"era": "August 1896", "origin": "Caloocan (Pugad Lawin / Balintawak)",
		"history": "Under Spain, every Filipino had to carry a cedula, a tax and identity paper. In August 1896, Andrés Bonifacio and the Katipuneros tore their cedulas apart and cried out for freedom. The Cry of Pugad Lawin began the Philippine Revolution. Historians still debate its exact day and place.",
		"flavor": "Tear the paper, free the people.",
		"color": Color("#E3D3A8"),  # paper cream
	},
	{
		"id": &"banton_cloth", "name": "Banton Burial Cloth", "cost": 160,
		"timing": Pamana.Timing.FIRST_WINDOW, "needs": Pamana.Needs.NOTHING,
		"effect": "Next trial: +15% move speed for the first 30 seconds.",
		"params": {"speed_multiplier": 1.15},
		"era": "13th–14th century", "origin": "Banton Island, Romblon",
		"history": "Found in 1936 in a burial cave on Banton Island, wrapped with human remains inside a wooden coffin. It is the oldest known ikat-dyed textile in the Philippines and one of the oldest in Southeast Asia, proof that weavers here mastered resist-dyeing long before the Spanish came. It is kept at the National Museum.",
		"flavor": "Woven to travel with the dead.",
		"color": Color("#5E7FD6"),  # indigo-blue
	},
	{
		"id": &"agimat", "name": "The Agimat", "cost": 100,
		"timing": Pamana.Timing.WHOLE_TRIAL, "needs": Pamana.Needs.NOTHING,
		"effect": "Next trial: your first three FAVOR losses are cancelled.",
		"params": {"charges": 3},
		"era": "Pre-colonial times to today", "origin": "Across the archipelago",
		"history": "An agimat, or anting-anting, is an amulet believed to protect its wearer from blades, bullets, sickness and evil spirits. Pre-colonial charms later mixed with Catholic images and Latin prayers, and many Katipuneros went into battle wearing one. Some Filipinos still keep them today.",
		"flavor": "Hindi tinatablan.",
		"color": Color("#B5823C"),  # bronze
	},
	{
		"id": &"mighty_pen", "name": "The Mighty Pen", "cost": 100,
		"timing": Pamana.Timing.FIRST_WINDOW, "needs": Pamana.Needs.Q_SKILL,
		"effect": "Next trial: your Q skill's cooldown is 20% shorter for the first 30 seconds.",
		"params": {"cooldown_multiplier": 0.8},
		"era": "1880s–1890s", "origin": "Manila, Madrid and Barcelona",
		"history": "Before the revolution came the Propaganda Movement. Reformists like José Rizal, Marcelo H. del Pilar and Graciano López Jaena fought Spanish abuses with writing: Rizal's novels Noli Me Tangere (1887) and El Filibusterismo (1891), and the newspaper La Solidaridad (1889). Their words woke a nation and inspired the Katipunan.",
		"flavor": "Mas matalim ang panulat kaysa sa tabak.",
		# Ink black: too dark for a frame on night indigo, so the card draws its
		# edge in ivory (UICards.pamana_edge).
		"color": Color("#26283A"),
	},
	{
		"id": &"mutya", "name": "The Mutya", "cost": 250,
		"timing": Pamana.Timing.FIRST_WINDOW, "needs": Pamana.Needs.NOTHING,
		"effect": "Next trial: +20% FAVOR gained for the first 30 seconds.",
		"params": {"gain_multiplier": 1.2},
		"era": "Folklore", "origin": "Tagalog and Visayan tales",
		"history": "In Filipino folklore, a mutya is a magical charm, such as a pearl, a stone, or a drop that falls from a banana blossom at midnight, that gives its keeper strength, luck or charm. The tales say you must catch it before it touches the ground and guard it from the spirits who want it back. Today the word also names a muse or a beauty queen.",
		"flavor": "Catch it before it falls.",
		"color": Color("#DCE3EA"),  # pearl
	},
	{
		"id": &"kampilan", "name": "Kampilan", "cost": 150,
		"timing": Pamana.Timing.WHOLE_TRIAL, "needs": Pamana.Needs.ANY_SKILL,
		"effect": "Next trial: the first skill you cast recharges instantly.",
		"params": {},
		"era": "27 April 1521", "origin": "Mactan, Cebu",
		"history": "The kampilan is a long, single-edged sword of the southern Philippines, with a forked tip. At the Battle of Mactan on 27 April 1521, the warriors of the chieftain Lapulapu defeated the Spanish expedition, and Ferdinand Magellan was killed. Lapulapu is often pictured with a kampilan and is honored as the first Filipino to resist foreign invaders.",
		"flavor": "Strike first, strike again.",
		"color": Color("#8E9BAE"),  # steel
	},
	{
		"id": &"surigao_gold", "name": "Surigao Gold", "cost": 50,
		"timing": Pamana.Timing.UNTIL_USED, "needs": Pamana.Needs.NOTHING,
		"effect": "Your next God's Due arrives 200 FAVOR before its milestone.",
		"params": {"early_by": 200},
		"era": "10th–13th century", "origin": "Surigao del Sur, Mindanao",
		"history": "In 1981, a hoard of gold was unearthed in Surigao del Sur: sashes, necklaces, rings and ornaments made by pre-colonial Filipino goldsmiths. The Surigao Treasure shows that polities like Butuan were rich and traded across Asia long before 1521. It is now in the collection of the Bangko Sentral ng Pilipinas.",
		"flavor": "The gods were not the only ones with gold.",
		"color": Color("#E8B84A"),  # gold (UITokens.GOLD)
	},
]

const WINDOW := 30.0  # every FIRST_WINDOW item lasts the first 30 seconds


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var icon: Texture2D = load(ICON)
	for spec in ITEMS:
		var item := Pamana.new()
		item.id = spec["id"]
		item.display_name = spec["name"]
		item.cost = spec["cost"]
		item.effect = spec["effect"]
		item.timing = spec["timing"]
		item.window = WINDOW if item.timing == Pamana.Timing.FIRST_WINDOW else 0.0
		item.params = spec["params"]
		item.era = spec["era"]
		item.origin = spec["origin"]
		item.history = spec["history"]
		item.flavor = spec["flavor"]
		item.needs = spec["needs"]
		item.color = spec["color"]
		item.icon = icon
		var path := "%s/%s.tres" % [OUT_DIR, str(item.id)]
		var err := ResourceSaver.save(item, path)
		print("saved %s -> %s (err=%d)" % [item.display_name, path, err])
	quit()
