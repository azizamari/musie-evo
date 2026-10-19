extends Node2D

# final_score = this level's score (boss reward, or a share of it on a loss)
signal game_over(won: bool, final_score: int)

enum Phase { COLLECT, BOSS, OVER }

@export var player: Area2D
@export var score_label: Label
@export var timer_label: Label
@export var camera: ShakeCamera
@export var player_health_bar: Range
@export var boss_health_bar: Range

@export_group("Game")
# Collect phase length, the boss comes when it hits 0
@export var game_duration: float = 30.0
# Show the how-to-play popup before the first round
@export var show_intro := true
# Artwork for the how-to-play popup. Empty = the popup is built in code
@export var intro_texture: Texture2D
# Points for beating this level's boss (level 1 = 5, level 2 = 10, level 3 = 15).
# Losing gives a share of it based on how much damage you did to the boss
@export var boss_reward: int = 15
# Show the score popup after the boss fight
@export var show_results := true
# Scene loaded after the score popup (R on the popup retries this level instead)
@export_file("*.tscn") var next_scene := "res://scenes/titlescreen.tscn"
# Optional font for the score popup (e.g. your graffiti font)
@export var results_font: Font

@export_group("Projectiles")
@export var projectile_scenes: Array[PackedScene] = []
@export var base_speed: float = 250.0
@export var speed_variance: float = 0.15
@export var spawn_margin: float = 40.0

@export_group("Difficulty")
@export var end_speed_multiplier: float = 2.0 # speed fi ekher l game
# avg seconds between spawns f start w f lekher
@export var start_interval: float = 1.4
@export var end_interval: float = 0.5

@export_group("Boss")
@export var boss_scene: PackedScene
@export var player_bullet_scene: PackedScene
# How much ammo each collected point is worth
@export var ammo_per_point: int = 1
# Boss resting distance from the right edge
@export var boss_x_from_right: float = 160.0

@export_group("Health Bars")
# Bars that float above the player's and the boss's heads
@export var head_bars := true
@export var player_bar_width: float = 90.0
@export var boss_bar_width: float = 160.0
@export var player_bar_color := Color(1.0, 0.45, 0.75)
@export var boss_bar_color := Color(0.7, 0.4, 1.0)

@export_group("Juice")
# Screen shake per point collected (1pt barely moves, 3pt is felt)
@export var collect_trauma_per_point: float = 0.18
# Screen shake when the algue stuns the player
@export var stun_trauma: float = 0.7
@export var boss_arrive_trauma: float = 0.6
@export var boss_hit_trauma: float = 0.1
@export var boss_rage_trauma: float = 0.5
@export var boss_death_trauma: float = 1.0
@export var player_hit_trauma: float = 0.5

var score := 0
var ammo := 0
var time_left := 0.0
var _phase := Phase.OVER
var _boss: Node = null
var _weights: Array[float] = []
var _total_weight := 0.0
var _spawn_timer := Timer.new()
var _bar_tweens := {}
var _player_bar: HeadBar
var _boss_bar: HeadBar


func _ready() -> void:
	assert(player != null, "Assign Player in the Main inspector")
	if projectile_scenes.is_empty():
		push_error("Add projectile scenes to Main > Projectile Scenes")
		return

	player.collected.connect(_on_collected)
	player.stunned.connect(_on_stunned)
	player.fire_requested.connect(_on_fire_requested)
	player.health_changed.connect(_on_player_health_changed)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)

	if head_bars:
		_player_bar = _make_head_bar(player, player_bar_width, player_bar_color)

	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_spawn)
	add_child(_spawn_timer)

	# Smooth, number-free bars
	for bar in [player_health_bar, boss_health_bar]:
		if bar:
			bar.step = 0.0
			if bar is ProgressBar:
				bar.show_percentage = false

	_cache_weights()
	if show_intro:
		_show_intro()
	else:
		start_game()


# Freeze everything behind the popup, start the round when it closes
func _show_intro() -> void:
	player.set_process(false)
	player.reset_for_round()
	time_left = game_duration
	_update_labels()

	var intro := IntroPanel.new()
	intro.boss_time = game_duration
	intro.projectile_scenes = projectile_scenes
	intro.panel_texture = intro_texture
	# Each player describes its own controls (fish: swim, hedgehog: jump)
	if player.has_method("intro_move"):
		var move: Dictionary = player.intro_move()
		intro.move_title = move.get("title", intro.move_title)
		intro.move_text = move.get("text", intro.move_text)
		intro.move_arrows = move.get("arrows", intro.move_arrows)
	intro.started.connect(start_game)
	add_child(intro)


func start_game() -> void:
	score = 0
	ammo = 0
	time_left = game_duration
	_phase = Phase.COLLECT

	if is_instance_valid(_boss):
		_boss.queue_free()
	_boss = null
	_boss_bar = null # freed together with the old boss
	if boss_health_bar:
		boss_health_bar.visible = false

	player.set_process(true)
	player.reset_for_round()
	_update_labels()
	_schedule_next()


func _process(delta: float) -> void:
	match _phase:
		Phase.COLLECT:
			time_left = maxf(time_left - delta, 0.0)
			_update_labels()
			if time_left <= 0.0:
				_start_boss_phase()
		Phase.BOSS:
			# Out of ammo with the boss alive = lose, once the last shots have landed
			if ammo <= 0 and get_tree().get_nodes_in_group("player_bullets").is_empty():
				_end_game(false, "ammo")


# 0.0 at the start of the round, 1.0 when time runs out
func _progress() -> float:
	return clampf(1.0 - time_left / maxf(game_duration, 0.01), 0.0, 1.0)


func _schedule_next() -> void:
	var interval := lerpf(start_interval, end_interval, _progress())
	_spawn_timer.start(interval * randf_range(0.7, 1.3))


func _spawn() -> void:
	if _phase != Phase.COLLECT:
		return

	var p = _pick_scene().instantiate()
	var size := get_viewport_rect().size

	# Extra margin for wobbling variants so they stay on screen.
	var wobble: float = p.wobble_amplitude
	var y_min: float = spawn_margin + wobble
	var y_max: float = size.y - spawn_margin - wobble
	# Players that can't reach the whole screen (hedgehog) give their own band
	if player.has_method("get_spawn_band"):
		var band: Vector2 = player.get_spawn_band()
		y_min = maxf(y_min, band.x + wobble)
		y_max = minf(y_max, band.y - wobble * 0.5)
	if y_min > y_max:
		y_min = (y_min + y_max) * 0.5
		y_max = y_min
	p.position = Vector2(size.x + spawn_margin, randf_range(y_min, y_max))

	var difficulty := lerpf(1.0, end_speed_multiplier, _progress())
	var variance := randf_range(1.0 - speed_variance, 1.0 + speed_variance)
	p.speed = base_speed * difficulty * p.speed_multiplier * variance

	add_child(p)
	_schedule_next()


# Read each scene's spawn_weight once so rarity lives on the projectile scene
func _cache_weights() -> void:
	_weights.clear()
	_total_weight = 0.0
	for scene in projectile_scenes:
		var temp = scene.instantiate()
		var w: float = temp.spawn_weight
		_weights.append(w)
		_total_weight += w
		temp.free()


func _pick_scene() -> PackedScene:
	var roll := randf() * _total_weight
	for i in projectile_scenes.size():
		roll -= _weights[i]
		if roll <= 0.0:
			return projectile_scenes[i]
	return projectile_scenes.back()


# --- Boss phase ---

func _start_boss_phase() -> void:
	_spawn_timer.stop()
	get_tree().call_group("projectiles", "queue_free")

	if boss_scene == null:
		push_error("Assign Boss Scene in the Main inspector")
		_end_game(true, "win")
		return

	_phase = Phase.BOSS

	# Points turn into ammo
	ammo = score * ammo_per_point
	player.can_shoot = ammo > 0

	var size := get_viewport_rect().size
	_boss = boss_scene.instantiate()
	_boss.target = player

	# Keep the boss inside the player's reach (hedgehog), else center it
	var boss_y := size.y * 0.5
	if player.has_method("get_spawn_band"):
		var band: Vector2 = player.get_spawn_band()
		boss_y = (band.x + band.y) * 0.5
		# Only bosses that patrol have this (the hedgie boss stands on the platform)
		if "patrol_amplitude" in _boss:
			_boss.patrol_amplitude = minf(_boss.patrol_amplitude, (band.y - band.x) * 0.5)
	_boss.position = Vector2(size.x + 200.0, boss_y)
	_boss.health_changed.connect(_on_boss_health_changed)
	_boss.hit.connect(_on_boss_hit)
	_boss.enraged.connect(_on_boss_enraged)
	_boss.died.connect(_on_boss_died)

	if boss_health_bar:
		boss_health_bar.visible = true
		boss_health_bar.value = 0.0 # fills up as the boss arrives

	add_child(_boss)
	if head_bars:
		_boss_bar = _make_head_bar(_boss as Node2D, boss_bar_width, boss_bar_color)
		_boss_bar.set_health(_boss.health, _boss.max_health) # fills up as it arrives
	_boss.enter(Vector2(size.x - boss_x_from_right, boss_y))

	_shake(boss_arrive_trauma)
	_update_labels()


func _on_fire_requested(spawn_pos: Vector2) -> void:
	if _phase != Phase.BOSS or ammo <= 0 or player_bullet_scene == null:
		return
	ammo -= 1
	var b = player_bullet_scene.instantiate()
	b.position = spawn_pos
	add_child(b)
	if ammo <= 0:
		player.can_shoot = false
	_update_labels()


func _on_boss_health_changed(current: int, max_health: int) -> void:
	_set_bar(boss_health_bar, current, max_health)
	if is_instance_valid(_boss_bar):
		_boss_bar.set_health(current, max_health)


func _on_boss_hit(_damage: int) -> void:
	_shake(boss_hit_trauma)


func _on_boss_enraged() -> void:
	_shake(boss_rage_trauma)


func _on_boss_died() -> void:
	_shake(boss_death_trauma)
	_end_game(true, "win")


# --- Player ---

func _on_collected(value: int) -> void:
	if _phase != Phase.COLLECT:
		return
	score += value
	_update_labels()
	_shake(collect_trauma_per_point * value)


func _on_stunned(_duration: float) -> void:
	if _phase == Phase.COLLECT:
		_shake(stun_trauma)


func _on_player_health_changed(current: int, max_health: int) -> void:
	_set_bar(player_health_bar, current, max_health)
	if is_instance_valid(_player_bar):
		_player_bar.set_health(current, max_health)


func _on_player_damaged(_amount: int) -> void:
	_shake(player_hit_trauma)


func _on_player_died() -> void:
	_end_game(false, "died")


# --- Shared ---

func _shake(amount: float) -> void:
	if camera:
		camera.add_trauma(amount)


# Tween the bar instead of snapping so damage reads as a drain
func _make_head_bar(target: Node2D, width: float, color: Color) -> HeadBar:
	var bar := HeadBar.new()
	bar.setup(target, width, color)
	return bar


func _set_bar(bar: Range, current: int, max_value: int) -> void:
	if bar == null:
		return
	bar.max_value = max_value
	if _bar_tweens.has(bar) and _bar_tweens[bar].is_valid():
		_bar_tweens[bar].kill()
	var tw := create_tween()
	tw.tween_property(bar, "value", float(current), 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bar_tweens[bar] = tw


# reason: "win", "died" (health ran out) or "ammo" (no ammo left)
func _end_game(won: bool, reason: String = "") -> void:
	if _phase == Phase.OVER:
		return
	_phase = Phase.OVER
	_spawn_timer.stop()
	player.can_shoot = false
	player.set_process(false)
	get_tree().call_group("projectiles", "queue_free")
	get_tree().call_group("enemy_bullets", "queue_free")
	get_tree().call_group("player_bullets", "queue_free")
	if not won and is_instance_valid(_boss):
		_boss.stop()

	# Win = full reward. Loss = share of the reward matching the damage done
	var damage := 1.0 if won else _boss_damage_ratio()
	var level_score := boss_reward if won else floori(boss_reward * damage)
	game_over.emit(won, level_score)

	if show_results:
		# Short pause so the boss death or the final hit can play out first
		get_tree().create_timer(1.0 if won else 0.8).timeout.connect(
			_show_results.bind(won, reason, level_score, damage))


# 0.0 = boss untouched, 1.0 = boss at zero health
func _boss_damage_ratio() -> float:
	if not is_instance_valid(_boss):
		return 0.0
	var max_hp := maxf(float(_boss.max_health), 1.0)
	return clampf(1.0 - float(_boss.health) / max_hp, 0.0, 1.0)


func _show_results(won: bool, reason: String, level_score: int, damage: float) -> void:
	var panel := ResultPanel.new()
	panel.won = won
	panel.reason = reason
	panel.score = level_score
	panel.max_score = boss_reward
	panel.damage = damage
	panel.next_scene = next_scene
	panel.font = results_font
	add_child(panel)


func _update_labels() -> void:
	if score_label:
		if _phase == Phase.BOSS:
			score_label.text = "Ammo: %d" % ammo
		else:
			score_label.text = "Points: %d" % score
	if timer_label:
		if _phase == Phase.BOSS:
			timer_label.text = "BOSS"
		else:
			timer_label.text = "Time: %d" % ceili(time_left)
