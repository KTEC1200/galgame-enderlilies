extends Control
## ENDER LILIES —— 视觉小说运行时 v0.1
##
## 架构：引擎不包含任何剧情；全部剧情来自 data/story.json（line / stage / jump
## 三种节点）。美术缺失时自动降级为按文件名着色的占位图，音乐缺失只记错误，
## 不中断流程。数据格式见 docs/数据规范.md。

const STORY_PATH := "res://data/story.json"
const MUSIC_PATH := "res://data/music_catalog.json"
const ART := "res://assets/"
const SAVE_VERSION := "el-vn-1"
const SLOT_PREFIX := "el_slot_"
const RESUME_PATH := "user://el_resume.json"

const SPEAKER_COLORS := {
	"lily": "dfe6f0",
	"knight": "9db4d8",
	"siegrid": "c9b8dd",
	"true_lily": "f0e6f0",
	"我": "a8c4b2",
	"": "8b95a3",
}

# ---- 剧情数据与运行状态 ----
var data: Dictionary = {}
var nodes: Array = []
var lookup: Dictionary = {}
var cursor: int = 0
var current: Dictionary = {}
var flags: Dictionary = {}
var cast: Array = []
var bg_id: String = "black"
var cg_id: String = ""
var chapter: String = ""
var scene_title: String = ""
var finished: bool = false
var in_title: bool = true
var ui_hidden: bool = false
var modal_open: bool = false

# ---- 打字机 ----
var typewriter_enabled: bool = true
var typewriter_active: bool = false
var typewriter_text: String = ""
var typewriter_index: int = 0
var typewriter_timer: Timer

# ---- 缓存与错误 ----
var tex_cache: Dictionary = {}
var render_errors: Array = []
var music_name: String = ""

# ---- UI 引用 ----
var bg: TextureRect
var actors: Control
var cg: TextureRect
var hud: Control
var speaker_label: Label
var body_label: RichTextLabel
var choice_box: VBoxContainer
var hint: Label
var title_screen: Control
var continue_button: Button
var overlay: Control
var overlay_box: VBoxContainer
var bgm: Node


func _ready() -> void:
	_build_theme()
	var file := FileAccess.open(STORY_PATH, FileAccess.READ)
	if file == null:
		push_error("无法打开剧情数据: " + STORY_PATH)
		return
	data = JSON.parse_string(file.get_as_text())
	nodes = data.get("nodes", [])
	for i in range(nodes.size()):
		lookup[str(nodes[i]["id"])] = i
	bgm = load("res://BgmPlayer.gd").new()
	add_child(bgm)
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_PATH))
	if catalog is Dictionary:
		bgm.configure(catalog)
	_build_ui()
	typewriter_timer = Timer.new()
	typewriter_timer.wait_time = 0.03
	typewriter_timer.timeout.connect(_typewriter_tick)
	add_child(typewriter_timer)
	if DisplayServer.get_name() != "headless":
		get_window().title = "ENDER LILIES · 终焉之雨 · v%s" % ProjectSettings.get_setting("application/config/version", "0.1")
	_show_title()
	if OS.get_cmdline_user_args().has("--smoke"):
		_run_smoke()


# ---------------------------------------------------------------- UI 构建

func _build_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	var theme_new := Theme.new()
	theme_new.default_font = font
	theme_new.default_font_size = 24
	theme = theme_new

func _panel_style(fill: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", Color("c9d4e4"))
	b.add_theme_color_override("font_hover_color", Color("eef3fa"))
	b.add_theme_color_override("font_pressed_color", Color("ffffff"))
	b.add_theme_color_override("font_disabled_color", Color("5c6674"))
	b.add_theme_stylebox_override("normal", _panel_style(Color("141a24e6"), Color("46536a99")))
	b.add_theme_stylebox_override("hover", _panel_style(Color("1d2736f0"), Color("7d93b5")))
	b.add_theme_stylebox_override("pressed", _panel_style(Color("28344a"), Color("9db4d8")))
	b.add_theme_stylebox_override("disabled", _panel_style(Color("10151d80"), Color("2c354255")))
	b.pressed.connect(action)
	return b

func _image(parent: Node) -> TextureRect:
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

func _build_ui() -> void:
	var black := ColorRect.new()
	black.color = Color("070a10")
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	bg = _image(self)
	actors = Control.new()
	actors.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(actors)
	cg = _image(self)
	cg.visible = false
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	var header := Label.new()
	header.name = "Header"
	header.position = Vector2(24, 14)
	header.add_theme_font_size_override("font_size", 17)
	header.add_theme_color_override("font_color", Color("7d8ea6"))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(header)

	var panel := Panel.new()
	panel.name = "DialoguePanel"
	panel.position = Vector2(30, 500)
	panel.size = Vector2(1220, 190)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(Color("0b1019cc"), Color("3c4a6180"), 12))
	hud.add_child(panel)

	speaker_label = Label.new()
	speaker_label.position = Vector2(56, 478)
	speaker_label.add_theme_font_size_override("font_size", 26)
	speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(speaker_label)

	body_label = RichTextLabel.new()
	body_label.position = Vector2(62, 540)
	body_label.size = Vector2(1156, 128)
	body_label.bbcode_enabled = false
	body_label.scroll_active = false
	body_label.add_theme_font_size_override("normal_font_size", 24)
	body_label.add_theme_color_override("default_color", Color("dde4ee"))
	body_label.add_theme_constant_override("line_separation", 7)
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(body_label)

	hint = Label.new()
	hint.position = Vector2(62, 662)
	hint.text = "空格 / 点击推进　·　Esc 菜单"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("5f6c80"))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hint)

	choice_box = VBoxContainer.new()
	choice_box.position = Vector2(160, 140)
	choice_box.size = Vector2(960, 0)
	choice_box.add_theme_constant_override("separation", 12)
	hud.add_child(choice_box)

	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 30
	overlay.visible = false
	add_child(overlay)
	overlay_box = VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 8)
	overlay_box.set_anchors_preset(Control.PRESET_CENTER)
	overlay_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(overlay_box)

	_build_title_screen()

func _build_title_screen() -> void:
	title_screen = Control.new()
	title_screen.name = "TitleScreen"
	title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_screen.z_index = 20
	add_child(title_screen)
	_image(title_screen)
	var dim := ColorRect.new()
	dim.color = Color("070a1066")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(dim)
	var name_label := Label.new()
	name_label.text = "ENDER LILIES"
	name_label.position = Vector2(84, 170)
	name_label.add_theme_font_size_override("font_size", 52)
	name_label.add_theme_color_override("font_color", Color("dfe6f0"))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(name_label)
	var sub_label := Label.new()
	sub_label.text = "终焉之雨 · 同人视觉小说（开发中样章）"
	sub_label.position = Vector2(88, 240)
	sub_label.add_theme_font_size_override("font_size", 20)
	sub_label.add_theme_color_override("font_color", Color("9db4d8"))
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(sub_label)
	var menu := VBoxContainer.new()
	menu.position = Vector2(88, 340)
	menu.add_theme_constant_override("separation", 8)
	title_screen.add_child(menu)
	for item in [["从头开始", "start"], ["继续游戏", "continue"], ["读取存档", "load"], ["离开游戏", "quit"]]:
		var b := _button(item[0], _menu.bind(item[1]))
		b.custom_minimum_size = Vector2(280, 44)
		b.add_theme_font_size_override("font_size", 19)
		menu.add_child(b)
		if item[1] == "continue":
			continue_button = b
	var footer := Label.new()
	footer.text = "同人作品 · 免费发布 · ENDER LILIES © Live Wire / Adglobe"
	footer.position = Vector2(88, 668)
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color("5f6c80"))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(footer)


# ---------------------------------------------------------------- 标题与菜单

func _show_title() -> void:
	in_title = true
	finished = false
	ui_hidden = false
	hud.visible = false
	actors.visible = false
	cg.visible = false
	choice_box.visible = false
	title_screen.visible = true
	bg.texture = _texture(ART + "key_visual.png")
	continue_button.disabled = not _has_resume()
	_music("title")

func start() -> void:
	cursor = 0
	flags = data.get("initial_flags", {}).duplicate(true)
	cast = []
	bg_id = "black"
	cg_id = ""
	chapter = ""
	scene_title = ""
	current = {}
	finished = false
	in_title = false
	ui_hidden = false
	title_screen.visible = false
	hud.visible = true
	choice_box.visible = true
	_show_next()

func _open_overlay(title: String, buttons: Array) -> void:
	modal_open = true
	overlay.visible = true
	for child in overlay_box.get_children():
		child.queue_free()
	var caption := Label.new()
	caption.text = title
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color("dfe6f0"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(caption)
	for item in buttons:
		var b: Button = item[0]
		b.custom_minimum_size = Vector2(460, 42)
		overlay_box.add_child(b)
	var close := _button("关闭", _close_overlay)
	close.custom_minimum_size = Vector2(460, 42)
	overlay_box.add_child(close)

func _close_overlay() -> void:
	modal_open = false
	overlay.visible = false

func _menu(kind: String) -> void:
	match kind:
		"start":
			start()
		"continue":
			_load_state(RESUME_PATH)
		"quit":
			get_tree().quit()
		"back_title":
			_close_overlay()
			_show_title()
		"save":
			_slots(true)
		"load":
			_slots(false)
		"resume":
			_close_overlay()

func _game_menu() -> void:
	_open_overlay("暂歇", [
		[_button("继续", _menu.bind("resume"))],
		[_button("保存", _menu.bind("save"))],
		[_button("读取", _menu.bind("load"))],
		[_button("回到标题", _menu.bind("back_title"))],
		[_button("离开游戏", _menu.bind("quit"))],
	])


# ---------------------------------------------------------------- 剧情执行

func _condition(requirements: Variant) -> bool:
	if requirements is Array:
		for requirement in requirements:
			if not _condition(requirement):
				return false
		return true
	for key in requirements:
		var actual: Variant = flags.get(key)
		var expected: Variant = requirements[key]
		if expected is Dictionary:
			if expected.has("neq") and actual == expected["neq"]:
				return false
			if expected.has("gte") and (actual == null or actual < expected["gte"]):
				return false
			if expected.has("lte") and (actual == null or actual > expected["lte"]):
				return false
		elif actual != expected:
			return false
	return true

func _goto(id: String) -> void:
	if not lookup.has(id):
		push_error("剧情跳转目标不存在: " + id)
		finished = true
		return
	cursor = int(lookup[id])

func _apply_stage(d: Dictionary) -> void:
	bg_id = str(d.get("bg", bg_id))
	chapter = str(d.get("date", chapter))
	scene_title = str(d.get("title", scene_title))
	if d.has("cast"):
		cast = d["cast"].duplicate(true)
	if d.has("cg"):
		cg_id = str(d["cg"])
	if d.has("set"):
		for key in d["set"]:
			flags[key] = d["set"][key]
	if d.has("music"):
		_music(str(d["music"]), str(d.get("music_outro", "")))
	hud.get_node("Header").text = _header_caption()

func _header_caption() -> String:
	if chapter != "" and scene_title != "":
		return chapter + "　·　" + scene_title
	return chapter + scene_title

func _show_next() -> void:
	var guard := 0
	while cursor < nodes.size() and guard < 10000:
		guard += 1
		var d: Dictionary = nodes[cursor]
		if d.has("when") and not _condition(d["when"]):
			cursor += 1
			continue
		var kind := str(d.get("type", "line"))
		if kind == "jump":
			_goto(str(d.get("next", "")))
			continue
		if kind == "stage":
			_apply_stage(d)
			cursor += 1
			continue
		if d.has("set"):
			for key in d["set"]:
				flags[key] = d["set"][key]
		current = d
		_render(d)
		return
	if guard >= 10000:
		push_error("剧情推进循环过多，请检查 when / jump")
	else:
		_finish()

func _render(d: Dictionary) -> void:
	typewriter_timer.stop()
	for child in choice_box.get_children():
		child.queue_free()
	var resolved: Dictionary = d.duplicate(true)
	for variant in d.get("variants", []):
		if _condition(variant.get("when", {})):
			for key in ["text", "speaker", "expression", "reactions"]:
				if variant.has(key):
					resolved[key] = variant[key]
			break
	var who := str(resolved.get("speaker", ""))
	var text := str(resolved.get("text", ""))
	var reactions: Dictionary = resolved.get("reactions", {})
	# 说话人不在舞台上时自动登场（容错，与参考实现一致）。
	if who != "" and who != "我" and str(data.get("cast_names", {}).get(who, "")) != "":
		var on_stage := false
		for actor in cast:
			if str(actor["id"]) == who:
				on_stage = true
		if not on_stage:
			cast.append({"id": who, "expression": str(resolved.get("expression", "normal"))})
	for actor in cast:
		var actor_id := str(actor["id"])
		if reactions.has(actor_id):
			actor["expression"] = str(reactions[actor_id])
		elif actor_id == who:
			actor["expression"] = str(resolved.get("expression", actor.get("expression", "normal")))
	_draw_cast(who)
	cg.texture = _texture(ART + "cg/" + cg_id + ".png") if cg_id != "" else null
	cg.visible = cg.texture != null
	actors.visible = not cg.visible and not in_title
	if bg_id == "black":
		bg.texture = null
	else:
		bg.texture = _texture(ART + "backgrounds/" + bg_id + ".png")
	speaker_label.text = _display_name(who) if who != "我" else who
	speaker_label.visible = who != ""
	speaker_label.add_theme_color_override("font_color", Color(SPEAKER_COLORS.get(who, "aeb8c6")))
	var is_narration := who == ""
	body_label.add_theme_color_override("default_color", Color("aebac9") if is_narration else Color("e2e8f2"))
	typewriter_text = text
	typewriter_index = 0
	typewriter_active = typewriter_enabled and not text.is_empty()
	body_label.text = text
	body_label.visible_characters = 0 if typewriter_active else -1
	if typewriter_active:
		typewriter_timer.start()
	var choices: Array = d.get("choices", [])
	choice_box.visible = not choices.is_empty()
	hint.text = "请选择" if not choices.is_empty() else "空格 / 点击推进　·　Esc 菜单"
	for option in choices:
		var b := _button(str(option["label"]), choose.bind(option))
		b.custom_minimum_size = Vector2(960, 52)
		b.add_theme_font_size_override("font_size", 21)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		choice_box.add_child(b)
	_write_json(RESUME_PATH, _save_data())

func _display_name(actor_id: String) -> String:
	# 内部 id → 显示名。映射表由 docs/数据规范.md 维护，剧情文本里也可直接写中文。
	return str(data.get("cast_names", {}).get(actor_id, actor_id))

func _draw_cast(speaker: String) -> void:
	for child in actors.get_children():
		actors.remove_child(child)
		child.free()
	var count := cast.size()
	if count == 0:
		return
	var centres: Array = []
	if count == 1:
		centres = [640.0]
	elif count == 2:
		centres = [430.0, 850.0]
	else:
		for i in range(count):
			centres.append(200.0 + 880.0 * float(i) / float(count - 1))
	# 说话人最后绘制（在最上层），其余压暗。
	var ordered: Array = []
	for actor in cast:
		if str(actor["id"]) != speaker:
			ordered.append(actor)
	for actor in cast:
		if str(actor["id"]) == speaker:
			ordered.append(actor)
	for actor in ordered:
		var actor_id := str(actor["id"])
		var expression := str(actor.get("expression", "normal"))
		var form := str(actor.get("form", "normal"))
		var path: String = ART + (("chibi/" if form == "chibi" else "sprites/") + actor_id + "/" + expression + ".png")
		var portrait := TextureRect.new()
		portrait.texture = _texture(path)
		if portrait.texture == null and expression != "normal":
			path = ART + (("chibi/" if form == "chibi" else "sprites/") + actor_id + "/normal.png")
			portrait.texture = _texture(path)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.size = Vector2(320, 460) if form == "chibi" else Vector2(640, 980)
		portrait.position = Vector2(centres[cast.find(actor)] - portrait.size.x / 2.0, -120.0)
		portrait.modulate = Color.WHITE if speaker == "" or actor_id == speaker else Color(0.55, 0.60, 0.70)
		actors.add_child(portrait)

func choose(option: Dictionary) -> void:
	if modal_open or in_title:
		return
	for key in option.get("set", {}):
		flags[key] = option["set"][key]
	current = {}
	_goto(str(option["next"]))
	_show_next()

func advance() -> void:
	if in_title or modal_open or finished:
		return
	if ui_hidden:
		_hide_ui(false)
		return
	if typewriter_active:
		_complete_typing()
		return
	if not current.get("choices", []).is_empty():
		return
	current = {}
	cursor += 1
	_show_next()

func _finish() -> void:
	finished = true
	current = {}
	typewriter_active = false
	typewriter_timer.stop()
	body_label.visible_characters = -1
	speaker_label.visible = false
	body_label.text = "—— 样章到这里暂时告一段落 ——"
	hint.text = "Esc 可回到标题重新开始"
	choice_box.visible = false
	var b := _button("回到标题", _menu.bind("back_title"))
	b.custom_minimum_size = Vector2(960, 52)
	choice_box.add_child(b)
	choice_box.visible = true

# ---------------------------------------------------------------- 打字机

func _typewriter_tick() -> void:
	if not typewriter_active:
		typewriter_timer.stop()
		return
	if in_title or modal_open or ui_hidden or finished:
		return
	typewriter_index += 1
	body_label.visible_characters = mini(typewriter_index, typewriter_text.length())
	if typewriter_index >= typewriter_text.length():
		_complete_typing()

func _complete_typing() -> void:
	typewriter_active = false
	typewriter_timer.stop()
	body_label.text = typewriter_text
	body_label.visible_characters = -1

# ---------------------------------------------------------------- 音乐

func _music(cue: String, outro: String = "") -> void:
	if cue == "":
		return
	if bgm.play(cue, outro):
		music_name = bgm.current_id

# ---------------------------------------------------------------- 存读档

func _save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"node": current.get("id", ""),
		"flags": flags.duplicate(true),
		"cast": cast.duplicate(true),
		"bg": bg_id,
		"cg": cg_id,
		"chapter": chapter,
		"title": scene_title,
		"music": music_name,
		"finished": finished,
		"time": Time.get_datetime_string_from_system(),
	}

func _slot_path(slot: int) -> String:
	return "user://" + SLOT_PREFIX + str(slot) + ".json"

func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload))
	else:
		push_error("写入失败: " + path)

func _has_resume() -> bool:
	if not FileAccess.file_exists(RESUME_PATH):
		return false
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(RESUME_PATH))
	return saved is Dictionary and saved.get("version") == SAVE_VERSION and lookup.has(str(saved.get("node", "")))

func _existing_slots() -> Array[int]:
	var slots: Array[int] = []
	var directory := DirAccess.open("user://")
	if directory == null:
		return slots
	for filename in directory.get_files():
		if not filename.begins_with(SLOT_PREFIX) or not filename.ends_with(".json"):
			continue
		var digits := filename.trim_prefix(SLOT_PREFIX).trim_suffix(".json")
		if digits.is_valid_int() and int(digits) > 0:
			slots.append(int(digits))
	slots.sort()
	return slots

func _slots(save_mode: bool) -> void:
	var buttons: Array = []
	if save_mode:
		var existing := _existing_slots()
		var next_slot: int = 1 if existing.is_empty() else int(existing.back()) + 1
		buttons.append([_button("＋ 新建存档", _save_slot.bind(next_slot))])
	for slot in _existing_slots():
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_slot_path(slot)))
		var valid: bool = saved is Dictionary and saved.get("version") == SAVE_VERSION and lookup.has(str(saved.get("node", "")))
		var description := "（空）"
		if saved is Dictionary:
			description = "%s · %s\n%s" % [saved.get("chapter", ""), saved.get("title", ""), saved.get("time", "")]
		var b := _button("存档 %d　%s" % [slot, description], _save_slot.bind(slot) if save_mode else _load_slot.bind(slot))
		b.disabled = not save_mode and not valid
		buttons.append([b])
	_open_overlay("保存旅程" if save_mode else "读取旅程", buttons)

func _save_slot(slot: int) -> void:
	_write_json(_slot_path(slot), _save_data())
	_close_overlay()

func _load_slot(slot: int) -> void:
	_load_state(_slot_path(slot))

func _load_state(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var saved: Dictionary = parsed
	if saved.get("version") != SAVE_VERSION:
		push_error("存档版本不匹配: " + path)
		return
	var node := str(saved.get("node", ""))
	if not lookup.has(node):
		push_error("存档指向的剧情节点已不存在: " + node)
		return
	_close_overlay()
	flags = saved.get("flags", {}).duplicate(true)
	cast = saved.get("cast", []).duplicate(true)
	bg_id = str(saved.get("bg", "black"))
	cg_id = str(saved.get("cg", ""))
	chapter = str(saved.get("chapter", ""))
	scene_title = str(saved.get("title", ""))
	music_name = str(saved.get("music", ""))
	if music_name != "":
		_music(music_name)
	var header: Label = hud.get_node("Header")
	header.text = _header_caption()
	finished = false
	in_title = false
	ui_hidden = false
	title_screen.visible = false
	hud.visible = true
	choice_box.visible = true
	_goto(node)
	_show_next()

# ---------------------------------------------------------------- 占位图

func _texture(path: String) -> Texture2D:
	if tex_cache.has(path):
		return tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		tex = _placeholder_for(path)
		_render_error_once("缺少美术资源（已用占位图顶替）: " + path)
	tex_cache[path] = tex
	return tex

func _placeholder_for(path: String) -> Texture2D:
	var seed_text := path.replace(ART, "").replace(".png", "")
	var hue := float(abs(hash(seed_text) % 360)) / 360.0
	var base := Color.from_hsv(hue, 0.18, 0.42)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([base.darkened(0.35), base.lightened(0.15)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 16
	tex.height = 16
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	return tex

func _render_error_once(detail: String) -> void:
	if not render_errors.has(detail):
		render_errors.append(detail)
		push_error(detail)

# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H and not in_title and not modal_open:
			_hide_ui(not ui_hidden)
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_SPACE, KEY_ENTER]:
			advance()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if modal_open:
				_close_overlay()
			elif not in_title:
				_game_menu()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not in_title and not modal_open:
			if ui_hidden:
				_hide_ui(false)
			else:
				advance()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not in_title and not modal_open:
			_hide_ui(not ui_hidden)
			get_viewport().set_input_as_handled()

func _hide_ui(hidden: bool) -> void:
	ui_hidden = hidden
	hud.visible = not hidden

# ---------------------------------------------------------------- 冒烟测试
## godot --headless --path . -- --smoke
## 两个分支各跑一遍：必须到达结尾、无渲染错误、无缺失音频。

var smoke_branch: int = 0

func _run_smoke() -> void:
	await get_tree().process_frame
	var all_ok := true
	for branch in [0, 1]:
		smoke_branch = branch
		var visited := {}
		var pages := 0
		var roundtrip_done := false
		start()
		var guard := 0
		while not finished and guard < 20000:
			guard += 1
			await get_tree().process_frame
			if finished:
				break
			if typewriter_active:
				_complete_typing()
			if current.is_empty():
				continue
			visited[str(current.get("id", ""))] = true
			pages += 1
			# 分支 0 中途做一次 存档→读档 往返，确认状态能完整还原。
			if branch == 0 and pages == 6 and not roundtrip_done:
				roundtrip_done = true
				var snapshot := _save_data()
				_save_slot(1)
				current = {}
				_load_slot(1)
				if str(current.get("id", "")) != str(snapshot["node"]) or flags.get("curious") != snapshot["flags"].get("curious"):
					all_ok = false
					print("SMOKE 存读档往返不一致: node=%s vs %s" % [str(current.get("id", "")), str(snapshot["node"])])
			var choices: Array = current.get("choices", [])
			if not choices.is_empty():
				var index: int = min(smoke_branch, choices.size() - 1)
				choose(choices[index])
			else:
				advance()
		print("SMOKE pass branch=%d pages=%d visited=%d finished=%s" % [branch, pages, visited.size(), str(finished)])
		if not finished:
			all_ok = false
	if not bgm.missing.is_empty():
		all_ok = false
		print("SMOKE missing audio: " + str(bgm.missing))
	if not render_errors.is_empty():
		print("SMOKE art placeholders used (%d)，属正常（占位美术阶段）: 首条 = %s" % [render_errors.size(), str(render_errors[0])])
	if all_ok:
		print("SMOKE PASS")
		get_tree().quit(0)
	else:
		print("SMOKE FAIL")
		get_tree().quit(1)
