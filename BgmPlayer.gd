extends Node
## 双声道交叉淡入淡出 BGM 播放器。
##
## 曲目全部来自 data/music_catalog.json；普通曲循环播放，Boss 曲支持
## Intro→Outro 自动接力（Intro 不循环，播完交叉淡入 Outro 并循环）。
## 若 cue 未登记或文件缺失，只记录错误，不中断游戏。

var tracks: Dictionary = {}
var pairs: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var gains: Array[float] = [0.0, 0.0]
var current_index: int = 0
var current_player: AudioStreamPlayer
var current_id: String = ""
var level: float = 0.8
var fade_seconds: float = 1.2
var tween: Tween
var pending_outro: String = ""
var streams: Dictionary = {}
var missing: Array[String] = []


func configure(catalog: Dictionary) -> void:
	pairs = catalog.get("pairs", {})
	for entry in catalog.get("tracks", []):
		tracks[str(entry["id"])] = entry
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "BGMVoice%d" % i
		player.volume_db = -80.0
		add_child(player)
		players.append(player)
	current_player = players[0]

func play(requested: String, outro: String = "") -> bool:
	if not tracks.has(requested):
		if not missing.has(requested):
			missing.append(requested)
		push_error("未登记的 BGM cue: " + requested)
		return false
	if requested == current_id and current_player.playing:
		return true
	var stream := _stream_for(requested)
	if stream == null:
		return false
	_switch_to(requested, stream)
	# Boss 曲接力：Intro 播完自动切 Outro。
	pending_outro = ""
	var pair_id := outro if outro != "" else str(pairs.get(requested, ""))
	if pair_id != "" and tracks.has(pair_id):
		pending_outro = pair_id
	return true

func stop_music() -> void:
	pending_outro = ""
	if tween != null and tween.is_valid():
		tween.kill()
	players[current_index].stop()
	gains[current_index] = 0.0
	current_id = ""
	_apply_levels()

func _switch_to(id: String, stream: AudioStream) -> void:
	pending_outro = ""
	if tween != null and tween.is_valid():
		tween.kill()
	var outgoing := current_index
	var incoming := 1 - outgoing
	var old_gain := gains[outgoing]
	players[incoming].stop()
	players[incoming].stream = stream
	gains[incoming] = 0.0
	current_index = incoming
	current_player = players[incoming]
	current_id = id
	_apply_levels()
	# 同一声道可能被复用而旧的一次性连接尚未触发，先解除再连接。
	if current_player.finished.is_connected(_on_intro_finished):
		current_player.finished.disconnect(_on_intro_finished)
	current_player.finished.connect(_on_intro_finished, CONNECT_ONE_SHOT)
	current_player.play()
	tween = create_tween()
	tween.tween_method(func(t: float):
		gains[outgoing] = old_gain * cos(t * PI * 0.5)
		gains[incoming] = sin(t * PI * 0.5)
		_apply_levels(), 0.0, 1.0, fade_seconds)
	tween.tween_callback(func():
		players[outgoing].stop()
		gains[outgoing] = 0.0
		_apply_levels())

func _on_intro_finished() -> void:
	if pending_outro == "" or current_id == pending_outro:
		return
	if current_player.playing:
		return
	var outro := pending_outro
	play(outro)

func _stream_for(id: String) -> AudioStream:
	if streams.has(id):
		return streams[id]
	var path := str(tracks[id].get("path", ""))
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		if not missing.has(path):
			missing.append(path)
		push_error("BGM 文件缺失: " + path)
		return null
	stream.loop = not id.ends_with("_intro")
	streams[id] = stream
	return stream

func set_level(value: float) -> void:
	level = clampf(value, 0.0, 1.0)
	_apply_levels()

func _apply_levels() -> void:
	for i in range(players.size()):
		var amplitude := level * gains[i]
		players[i].volume_db = linear_to_db(amplitude) if amplitude > 0.0001 else -80.0
