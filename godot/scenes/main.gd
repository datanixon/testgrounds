extends Node2D
## M9 root router. Owns the persistent Session, loads prefs + probes the save at
## boot, and swaps the active screen scene whenever Session.screen changes. Screen
## scenes emit navigation signals; the router updates the Session and re-routes.
## (No class_name: this is the main scene entry point.)

const Session = preload("res://core/session.gd")
const SaveGame = preload("res://core/save_game.gd")
const TitleScene = preload("res://scenes/title/title_scene.gd")
const CampaignScene = preload("res://scenes/campaign/campaign_scene.gd")
const StoryScene = preload("res://scenes/story/story_scene.gd")
const GameoverScene = preload("res://scenes/gameover/gameover_scene.gd")
const MatchScene = preload("res://scenes/match/match_scene.gd")
const DeployScene = preload("res://scenes/deploy/deploy_scene.gd")
const DeployLib = preload("res://core/deploy.gd")
const Campaign = preload("res://data/campaign.gd")
const RosterStore = preload("res://core/roster_store.gd")

var session: Session
var _current: Node = null

func _ready() -> void:
	session = Session.new()
	session.load_prefs()
	session.screen = "title"
	_route()
	_maybe_shot()

## _maybe_shot — dev screenshot hook (visual validation). With `-- --shot <target>` on
## the command line, drive to a target screen, capture the window to tools/shots/, quit.
## Runs in the normal game so autoloads (Audio) are present. No-op without the flag.
## Targets: title | fog (fog-on skirmish) | mission2 (objective campaign mission).
func _maybe_shot() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i < 0:
		return
	var target: String = args[i + 1] if i + 1 < args.size() else "title"
	_run_shot(target)

func _run_shot(target: String) -> void:
	await get_tree().create_timer(0.4).timeout
	match target:
		"fog":
			session.settings["fog"] = true
			_on_begin_skirmish()
		"mission2":
			session.start_campaign(1)
			DeployLib.commit(session.state, [])
			session.screen = "play"
			_route()
		"skirmish":
			session.settings["fog"] = false
			session.start_skirmish()
			_route()
		"campaign":
			session.screen = "campaign"
			_route()
		"story":
			session.story_index = 0
			session.screen = "story"
			_route()
		"deploy":
			RosterStore.save(RosterStore.migrate(4))
			session.start_campaign(0)
			_route()
		"gameover":
			session.settings["fog"] = false
			session.start_skirmish()
			session.state.stats = {"summoned": [3, 2], "lost": [1, 2], "battles": 4}
			session.state.winner = 0
			session.screen = "gameover"
			_route()
		"settings":
			session.settings["fog"] = false
			session.start_skirmish()
			_route()
			await get_tree().create_timer(0.3).timeout
			_current.settings_panel.open(session)
		"selected":
			session.settings["fog"] = false
			session.start_skirmish()
			_route()
			await get_tree().create_timer(0.3).timeout
			var ms = _current.state.master_of(0)
			_current._on_click(Vector2i(ms["q"], ms["r"]))
		"menu":
			session.settings["fog"] = false
			session.start_skirmish()
			_route()
			await get_tree().create_timer(0.3).timeout
			var mm = _current.state.master_of(0)
			_current.selected = mm
			_current._open_menu_for(mm)
		"summon":
			session.settings["fog"] = false
			session.start_skirmish()
			_route()
			await get_tree().create_timer(0.3).timeout
			var mu = _current.state.master_of(0)
			_current.selected = mu
			_current._on_action_chosen("summon")
		"battle":
			session.start_skirmish()
			_route()
			await get_tree().create_timer(0.3).timeout
			_current.battle_scene.play({
				"attacker": {"type_key": "cinderling", "name": "Cinderling", "element": "pyro", "sprite": "imp", "owner": 0, "attack": "melee", "is_master": false},
				"defender": {"type_key": "galewisp", "name": "Galewisp", "element": "zephyr", "sprite": "wisp", "owner": 1, "attack": "spark", "is_master": false},
				"attacker_pos": Vector2i(0, 0),
				"atk_hp_before": 12, "atk_max_hp": 12, "def_hp_before": 10, "def_max_hp": 10,
				"primary": {"dmg": 6, "absorbed": false, "killed": false},
				"counter": {"happened": true, "dmg": 3, "absorbed": false, "killed": false},
				"status": null, "terrain": "plain",
			})
		_:
			pass   # title: capture the booted screen
	await get_tree().create_timer(0.9).timeout
	var dir := ProjectSettings.globalize_path("res://tools/shots/")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir + target + ".png")
	print("[SHOT] saved %s%s.png" % [dir, target])
	get_tree().quit()

## _route — free the current screen scene and build the one matching session.screen.
func _route() -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	match session.screen:
		"title":
			session.has_save = SaveGame.probe()
			var t := TitleScene.new()
			t.session = session
			t.begin_skirmish.connect(_on_begin_skirmish)
			t.open_campaign.connect(_on_open_campaign)
			t.continue_save.connect(_on_continue)
			_mount(t)
		"campaign":
			var c := CampaignScene.new()
			c.session = session
			c.pick_mission.connect(_on_pick_mission)
			c.back_to_title.connect(_on_to_title)
			_mount(c)
		"story":
			var s := StoryScene.new()
			s.session = session
			s.begin_mission.connect(_on_begin_mission)
			_mount(s)
		"deploy":
			var d := DeployScene.new()
			d.session = session
			d.scenario = Campaign.CAMPAIGN[session.story_index]
			d.begin_mission.connect(_on_deploy_begin)
			d.back.connect(_on_deploy_back)
			_mount(d)
		"play":
			var m := MatchScene.new()
			m.init(session.state, session)
			m.match_ended.connect(_on_match_ended)
			_mount(m)
		"gameover":
			var g := GameoverScene.new()
			g.set_result(session.state)
			g.to_title.connect(_on_to_title)
			_mount(g)

func _mount(node: Node) -> void:
	_current = node
	add_child(node)

func _go(screen: String) -> void:
	session.screen = screen
	_route()

# ---- navigation handlers ----

func _on_begin_skirmish() -> void:
	session.start_skirmish()    # sets screen = "play"
	_route()

func _on_open_campaign() -> void:
	_go("campaign")

func _on_continue() -> void:
	var loaded = SaveGame.load_game()
	if loaded == null:
		return
	session.state = loaded
	session.screen = "play"
	_route()

func _on_pick_mission(index: int) -> void:
	session.story_index = index
	_go("story")

func _on_begin_mission() -> void:
	session.start_campaign(session.story_index)   # sets screen = "deploy"
	_route()

func _on_deploy_begin(picked_entries: Array) -> void:
	DeployLib.commit(session.state, picked_entries)
	_go("play")

func _on_deploy_back() -> void:
	_go("campaign")

func _on_match_ended(_winner: int) -> void:
	# session.on_match_won already ran inside MatchScene; just show the result.
	_go("gameover")

## _on_to_title — leave campaign list or gameover for the title. Routes through
## Session.return_to_title so the finished match's GameState is released (not held
## stale until the next match) and the campaign tag is cleared.
func _on_to_title() -> void:
	session.return_to_title()   # sets screen = "title", state = null
	_route()
