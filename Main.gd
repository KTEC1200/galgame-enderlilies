extends Control
## 终焉之雨（ENDER LILIES 同人）—— 视觉小说运行时 v0.5
##
## 架构：引擎不包含任何剧情；全部剧情来自 data/story.json（line / stage / jump
## 三种节点，由 tools/build_story.py 从 story-src/*.md 编译生成）。
## 附加系统在 Extras.gd（图库 / 分支树 / 回看 / 设置）。
## 美术缺失时自动降级为按文件名着色的占位图，音乐缺失只记错误，不中断流程。
##
## v0.5 UI：参考图风格重构 —— 深底 + 蓝主色 + 黄绿点缀 + 阴影立体感；
## 鼠标点击/滚轮推进、右键返回、文本快进、连续滑杆设置、窗口尺寸切换。

const STORY_PATH := "res://data/story.json"
const MUSIC_PATH := "res://data/music_catalog.json"
const ART_INDEX_PATH := "res://data/art_index.json"
const FLOW_PATH := "res://data/flowchart.json"
const ART := "res://assets/"
const SAVE_VERSION := "el-vn-1"
const SLOT_PREFIX := "el_slot_"
const RESUME_PATH := "user://el_resume.json"
const PROFILE_PATH := "user://el_profile.json"

# ---- UI 调色板（深底 / 蓝主色 / 黄绿点缀）----
const COL_BG := "070a10"
const COL_BLUE := "2e6bff"
const COL_BLUE_SOFT := "7d93b5"
const COL_LIME := "c8f000"
const COL_TEXT := "e8edf6"
const COL_TEXT_DIM := "9aa5b8"
const COL_TEXT_FAINT := "5f6c80"

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

# ---- 自动播放 / 快进 ----
var auto_mode: bool = false
var playback_speed: float = 1.0
var text_speed: float = 45.0            # 文字速度（字/秒）
var skip_held: bool = false             # Ctrl 按住快进
var skip_active: bool = false           # 「快进」按钮开关
var skip_mode: String = "read"          # read=已读跳过 / all=全部跳过
var current_was_read: bool = false
var auto_timer: Timer
var dialogue_size: int = 26

# ---- 进度数据（持久化到 user://el_profile.json）----
var profile: Dictionary = {"version": 1, "unlocked": {}, "read": {}, "speed": 1.0, "typewriter": true, "volume": 0.8, "flow_seen": {}, "checkpoints": {}, "text_speed": 45.0, "skip_mode": "read", "display": "window"}
var progress_dirty: bool = false
var resume_dirty: bool = false
var progress_timer: Timer

# ---- 回看 / 图库 / 分支树数据 ----
var backlog: Array = []
var art_index: Dictionary = {}      # node_id -> {arts:[], title, chapter}
var gallery_items: Dictionary = {}  # art_key -> {category, title, locations:[]}
var flow_data: Dictionary = {}
var active_flow: String = ""
var checkpoint_flow: String = ""

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
var auto_button: Button
var skip_button: Button
var pulse_label: Label
var name_bar: ColorRect
var extras: Control
var bgm: Node


func _ready() -> void:
	# 根节点必须放行鼠标事件：否则整屏 STOP 会吞掉点击，剧情只能用空格推进。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_theme()
	var file := FileAccess.open(STORY_PATH, FileAccess.READ)
	if file == null:
		push_error("无法打开剧情数据: " + STORY_PATH)
		return
	data = JSON.parse_string(file.get_as_text())
	nodes = data.get("nodes", [])
	for i in range(nodes.size()):
		lookup[str(nodes[i]["id"])] = i
	_load_derived_data()
	_load_profile()
	bgm = load("res://BgmPlayer.gd").new()
	add_child(bgm)
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_PATH))
	if catalog is Dictionary:
		bgm.configure(catalog)
	bgm.set_level(float(profile.get("volume", 0.8)))
	_build_ui()
	extras = load("res://Extras.gd").new()
	extras.game = self
	add_child(extras)
	typewriter_timer = Timer.new()
	typewriter_timer.wait_time = 1.0 / text_speed
	typewriter_timer.timeout.connect(_typewriter_tick)
	add_child(typewriter_timer)
	auto_timer = Timer.new()
	auto_timer.one_shot = true
	auto_timer.timeout.connect(_auto_tick)
	add_child(auto_timer)
	progress_timer = Timer.new()
	progress_timer.wait_time = 0.6
	progress_timer.one_shot = true
	progress_timer.timeout.connect(_flush_profile)
	add_child(progress_timer)
	if DisplayServer.get_name() != "headless":
		_apply_display_mode()
		get_window().title = "终焉之雨 · v%s" % ProjectSettings.get_setting("application/config/version", "0.5")
	_show_title()
	if OS.get_cmdline_user_args().has("--smoke"):
		_run_smoke()
	elif OS.get_cmdline_user_args().has("--shots"):
		_run_shots()

func _load_derived_data() -> void:
	var art_file := FileAccess.open(ART_INDEX_PATH, FileAccess.READ)
	if art_file != null:
		art_index = JSON.parse_string(art_file.get_as_text())
	var flow_file := FileAccess.open(FLOW_PATH, FileAccess.READ)
	if flow_file != null:
		flow_data = JSON.parse_string(flow_file.get_as_text())
	# 图库条目：art key -> 类别 / 标题 / 解锁地点
	for node_id in art_index:
		var entry: Dictionary = art_index[node_id]
		var place := "%s · %s" % [entry.get("chapter", ""), entry.get("title", "")]
		for key in entry.get("arts", []):
			var parts: PackedStringArray = str(key).split("/")
			var category := str(parts[0])
			if not gallery_items.has(key):
				var title := str(parts[1])
				if category == "sprite" and parts.size() > 2:
					title = "%s · %s" % [_display_name(str(parts[1])), parts[2]]
				gallery_items[key] = {"category": category, "title": title, "locations": []}
			var locations: Array = gallery_items[key]["locations"]
			if not locations.has(place) and chapter + scene_title != "":
				locations.append(place)

func _display_name(actor_id: String) -> String:
	return str(data.get("cast_names", {}).get(actor_id, actor_id))


# ---------------------------------------------------------------- UI 构建

func _build_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	var theme_new := Theme.new()
	theme_new.default_font = font
	theme_new.default_font_size = 24
	theme = theme_new

func _panel_style(fill: Color, border: Color, radius: int = 10, shadow: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, 3)
	return s

func _button(text: String, action: Callable) -> Button:
	# 卡片按钮：左侧蓝条 + 悬停亮边 + 按下黄绿，配轻投影提供立体感
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", Color("c9d4e4"))
	b.add_theme_color_override("font_hover_color", Color("f2f6fc"))
	b.add_theme_color_override("font_pressed_color", Color(COL_LIME))
	b.add_theme_color_override("font_disabled_color", Color("5c6674"))
	var normal := _panel_style(Color("141b2ae6"), Color("2c3650"), 8)
	normal.border_width_left = 3
	normal.shadow_color = Color(0, 0, 0, 0.3)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 2)
	b.add_theme_stylebox_override("normal", normal)
	var hover := _panel_style(Color("1c2639f2"), Color(COL_BLUE_SOFT), 8)
	hover.border_width_left = 3
	b.add_theme_stylebox_override("hover", hover)
	var pressed := _panel_style(Color("22304a"), Color(COL_LIME), 8)
	pressed.border_width_left = 3
	b.add_theme_stylebox_override("pressed", pressed)
	var disabled := _panel_style(Color("10151d80"), Color("2c354255"), 8)
	disabled.border_width_left = 3
	b.add_theme_stylebox_override("disabled", disabled)
	b.pressed.connect(action)
	return b

func _flat_button(text: String, action: Callable) -> Button:
	# 对话框快捷条上的文字按钮：平时只有文字，悬停浮出亮底
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color("9aa5b8"))
	b.add_theme_color_override("font_hover_color", Color(COL_LIME))
	b.add_theme_color_override("font_pressed_color", Color("ffffff"))
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("1c2639b0")
	hover.set_corner_radius_all(6)
	hover.content_margin_left = 10
	hover.content_margin_right = 10
	hover.content_margin_top = 3
	hover.content_margin_bottom = 3
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(action)
	return b

func _diamond_texture(px: int, fill: Color, outline: Color) -> ImageTexture:
	# 滑杆菱形滑块（参考图样式）
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := (px - 1) / 2.0
	for y in px:
		for x in px:
			var d := absf(x - c) + absf(y - c)
			if d <= c - 1.5:
				img.set_pixel(x, y, fill)
			elif d <= c:
				img.set_pixel(x, y, outline)
	return ImageTexture.create_from_image(img)

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
	header.add_theme_color_override("font_color", Color("6c7a92"))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(header)

	# 对话框：深底 + 蓝边 + 投影，左上/右下角标呼应参考图
	var panel := Panel.new()
	panel.name = "DialoguePanel"
	panel.position = Vector2(30, 466)
	panel.size = Vector2(1220, 214)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(Color("0a0f18ee"), Color("2e6bff7a"), 12, 14))
	hud.add_child(panel)
	var accent := FrameAccent.new()
	accent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(accent)

	# 说话人名牌：黄绿短标 + 名字
	name_bar = ColorRect.new()
	name_bar.color = Color(COL_LIME)
	name_bar.position = Vector2(56, 448)
	name_bar.size = Vector2(5, 24)
	name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(name_bar)
	speaker_label = Label.new()
	speaker_label.position = Vector2(74, 440)
	speaker_label.add_theme_font_size_override("font_size", 24)
	speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(speaker_label)

	body_label = RichTextLabel.new()
	body_label.position = Vector2(74, 504)
	body_label.size = Vector2(1132, 124)
	body_label.bbcode_enabled = false
	body_label.scroll_active = false
	body_label.add_theme_font_size_override("normal_font_size", 24)
	body_label.add_theme_color_override("default_color", Color("dde4ee"))
	body_label.add_theme_constant_override("line_separation", 7)
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(body_label)

	hint = Label.new()
	hint.position = Vector2(74, 644)
	hint.text = "点击 / 空格推进　·　滚轮↑ 历史　·　Esc 菜单"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(COL_TEXT_FAINT))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hint)

	# 推进提示箭头（页面读完且非自动/快进时脉冲闪烁）
	pulse_label = Label.new()
	pulse_label.text = "▶"
	pulse_label.add_theme_font_size_override("font_size", 20)
	pulse_label.add_theme_color_override("font_color", Color(COL_LIME))
	pulse_label.position = Vector2(1204, 642)
	pulse_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse_label.visible = false
	hud.add_child(pulse_label)
	var pulse_tween := create_tween().set_loops()
	pulse_tween.tween_property(pulse_label, "modulate:a", 0.25, 0.55)
	pulse_tween.tween_property(pulse_label, "modulate:a", 1.0, 0.55)

	# 对话框内快捷文字菜单（参考图右下样式）
	var controls := HBoxContainer.new()
	controls.position = Vector2(660, 644)
	controls.add_theme_constant_override("separation", 12)
	hud.add_child(controls)
	for item in [["历史", "log"], ["快进", "skip"], ["自动", "auto"], ["保存", "save"], ["载入", "load"], ["设置", "settings"], ["隐藏", "hide_ui"], ["菜单", "menu"]]:
		var b := _flat_button(item[0], _quick.bind(item[1]))
		b.custom_minimum_size = Vector2(0, 28)
		controls.add_child(b)
		if item[1] == "auto":
			auto_button = b
		elif item[1] == "skip":
			skip_button = b

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
	overlay.gui_input.connect(func(event: InputEvent):
		# 右键单击返回（关闭弹窗）
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_close_overlay()
			get_viewport().set_input_as_handled())
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.add_theme_stylebox_override("panel", _panel_style(Color("0c1220f7"), Color("2e6bff88"), 16, 22))
	card.custom_minimum_size = Vector2(540, 0)
	overlay.add_child(card)
	overlay_box = VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 10)
	card.add_child(overlay_box)

	_build_title_screen()

func _build_title_screen() -> void:
	title_screen = Control.new()
	title_screen.name = "TitleScreen"
	title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_screen.z_index = 20
	add_child(title_screen)
	_image(title_screen)
	# 左侧渐变压暗（右透出立绘），比整片纯色遮罩更有层次
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([Color("05070de8"), Color("05070d99"), Color("05070d00")])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.width = 128
	grad_tex.height = 128
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(1, 0)
	shade.texture = grad_tex
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(shade)

	# 标题组：黄绿短杠 + 英文副题 + 大标题（蓝色错位阴影）
	var bar := ColorRect.new()
	bar.color = Color(COL_LIME)
	bar.position = Vector2(88, 116)
	bar.size = Vector2(56, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(bar)
	var sub_label := Label.new()
	sub_label.text = "ENDER LILIES FAN VISUAL NOVEL"
	sub_label.position = Vector2(88, 136)
	sub_label.add_theme_font_size_override("font_size", 17)
	sub_label.add_theme_color_override("font_color", Color(COL_BLUE_SOFT))
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(sub_label)
	var name_label := Label.new()
	name_label.text = "终焉之雨"
	name_label.position = Vector2(82, 166)
	name_label.add_theme_font_size_override("font_size", 84)
	name_label.add_theme_color_override("font_color", Color("f2f6fc"))
	name_label.add_theme_color_override("shadow_color", Color("2e6bff8c"))
	name_label.add_theme_constant_override("shadow_offset_x", 4)
	name_label.add_theme_constant_override("shadow_offset_y", 4)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(name_label)
	var tagline := Label.new()
	tagline.text = "把悲哀带往世界尽头 —— 同人视觉小说"
	tagline.position = Vector2(88, 284)
	tagline.add_theme_font_size_override("font_size", 17)
	tagline.add_theme_color_override("font_color", Color(COL_TEXT_DIM))
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(tagline)

	# 菜单：左侧蓝竖线，悬停时黄绿箭头滑入
	var menu_line := ColorRect.new()
	menu_line.color = Color(COL_BLUE)
	menu_line.position = Vector2(88, 342)
	menu_line.size = Vector2(3, 280)
	menu_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(menu_line)
	var arrow := Label.new()
	arrow.text = "▶"
	arrow.add_theme_font_size_override("font_size", 20)
	arrow.add_theme_color_override("font_color", Color(COL_LIME))
	arrow.position = Vector2(102, 348)
	arrow.visible = false
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(arrow)
	var menu := VBoxContainer.new()
	menu.position = Vector2(122, 336)
	menu.add_theme_constant_override("separation", 15)
	title_screen.add_child(menu)
	for item in [["继续游戏", "continue"], ["从头开始", "start"], ["读取存档", "load"], ["旅途图库", "gallery"], ["剧情分支树", "flowchart"], ["游戏设置", "settings"], ["离开游戏", "quit"]]:
		var b := Button.new()
		b.text = item[0]
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(280, 0)
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", Color("b9c4d6"))
		b.add_theme_color_override("font_hover_color", Color("ffffff"))
		b.add_theme_color_override("font_pressed_color", Color(COL_LIME))
		b.add_theme_color_override("font_disabled_color", Color("4d5666"))
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.pressed.connect(_menu.bind(item[1]))
		b.mouse_entered.connect(func():
			arrow.visible = true
			arrow.position.y = menu.position.y + b.position.y + 8)
		menu.add_child(b)
		if item[1] == "continue":
			continue_button = b
	menu.mouse_exited.connect(func(): arrow.visible = false)

	var footer := Label.new()
	footer.text = "v%s // 终焉之雨 · ENDER LILIES 同人作品 · 免费发布 · © Live Wire / Adglobe" % ProjectSettings.get_setting("application/config/version", "0.5")
	footer.position = Vector2(88, 676)
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(COL_TEXT_FAINT))
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
	_flush_profile()
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
	auto_mode = false
	skip_held = false
	skip_active = false
	_update_playback_buttons()
	backlog = []
	active_flow = ""
	checkpoint_flow = ""
	title_screen.visible = false
	hud.visible = true
	choice_box.visible = true
	_update_playback_buttons()
	_show_next()

func _is_modal() -> bool:
	return modal_open or extras.visible

func _open_overlay(title: String, buttons: Array) -> void:
	modal_open = true
	overlay.visible = true
	for child in overlay_box.get_children():
		child.queue_free()
	var caption := Label.new()
	caption.text = title
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color(COL_TEXT))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(caption)
	for item in buttons:
		var b: Button = item[0]
		b.custom_minimum_size = Vector2(460, 44)
		overlay_box.add_child(b)
	var close := _button("关闭", _close_overlay)
	close.custom_minimum_size = Vector2(460, 44)
	overlay_box.add_child(close)
	overlay_box.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(overlay_box, "modulate:a", 1.0, 0.12)
	_update_pulse()

func _close_overlay() -> void:
	modal_open = false
	overlay.visible = false
	_update_pulse()

func _quick(kind: String) -> void:
	# 对话框快捷条入口：快进/隐藏特殊处理，其余走菜单路由
	match kind:
		"skip":
			skip_active = not skip_active
			_update_playback_buttons()
			_schedule_auto()
		"hide_ui":
			_hide_ui(true)
		_:
			_menu(kind)

func _menu(kind: String) -> void:
	# 打开任何面板都退出快进态
	if not kind in ["auto", "skip", "resume", "start", "continue", "quit"]:
		skip_active = false
	match kind:
		"start":
			start()
		"continue":
			_load_state(RESUME_PATH)
		"quit":
			_flush_profile()
			get_tree().quit()
		"back_title":
			_close_overlay()
			_flush_profile()
			_show_title()
		"save":
			_slots(true)
		"load":
			_slots(false)
		"resume":
			_close_overlay()
		"menu":
			_game_menu()
		"log":
			extras.open("backlog")
		"gallery":
			extras.open("gallery")
		"flowchart":
			extras.open("flowchart")
		"settings":
			extras.open("settings")
		"auto":
			auto_mode = not auto_mode
			_update_playback_buttons()
			_schedule_auto()
		"game_menu":
			_game_menu()

func _game_menu() -> void:
	_open_overlay("暂歇", [
		[_button("继续", _menu.bind("resume"))],
		[_button("回看", _menu.bind("log"))],
		[_button("保存", _menu.bind("save"))],
		[_button("读取", _menu.bind("load"))],
		[_button("旅途图库", _menu.bind("gallery"))],
		[_button("剧情分支树", _menu.bind("flowchart"))],
		[_button("游戏设置", _menu.bind("settings"))],
		[_button("回到标题", _menu.bind("back_title"))],
		[_button("离开游戏", _menu.bind("quit"))],
	])

func _update_playback_buttons() -> void:
	if auto_button != null:
		auto_button.text = "自动·开" if auto_mode else "自动"
		auto_button.add_theme_color_override("font_color", Color(COL_LIME) if auto_mode else Color("9aa5b8"))
	if skip_button != null:
		skip_button.text = "快进·开" if skip_active else "快进"
		skip_button.add_theme_color_override("font_color", Color(COL_LIME) if skip_active else Color("9aa5b8"))


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

func _visible_choices(d: Dictionary) -> Array:
	# 选项级 @when 过滤；全部被过滤掉时按未过滤显示并报错（兜底防卡死）
	var choices: Array = d.get("choices", [])
	var visible: Array = []
	for option in choices:
		if _condition(option.get("when", {})):
			visible.append(option)
	if not choices.is_empty() and visible.is_empty():
		push_error("选项页 %s 所有选项均不满足条件" % str(d.get("id", "")))
		visible = choices
	return visible

func _goto(id: String) -> void:
	if not lookup.has(id):
		push_error("剧情跳转目标不存在: " + id)
		finished = true
		return
	cursor = int(lookup[id])

func _header_caption() -> String:
	if chapter != "" and scene_title != "":
		return chapter + "　·　" + scene_title
	return chapter + scene_title

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
	auto_timer.stop()
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
	name_bar.visible = who != ""
	speaker_label.add_theme_color_override("font_color", Color(SPEAKER_COLORS.get(who, "aeb8c6")))
	var is_narration := who == ""
	body_label.add_theme_color_override("default_color", Color("aebac9") if is_narration else Color("e2e8f2"))
	# 进度记录：已读 / 图库解锁 / 回看 / 分支树
	var node_id := str(d["id"])
	current_was_read = profile["read"].has(node_id)
	profile["read"][node_id] = true
	_progress_changed()
	_unlock_art(node_id)
	backlog.append({"speaker": _display_name(who) if who != "我" else who, "text": text, "chapter": chapter, "title": scene_title})
	if backlog.size() > 200:
		backlog.pop_front()
	_trace_flow(node_id)
	# 文本与演出
	typewriter_text = text
	typewriter_index = 0
	typewriter_active = typewriter_enabled and not text.is_empty()
	body_label.text = text
	body_label.add_theme_font_size_override("normal_font_size", dialogue_size)
	body_label.visible_characters = 0 if typewriter_active else -1
	if typewriter_active:
		typewriter_timer.start()
	var visible_choices: Array = _visible_choices(d)
	choice_box.visible = not visible_choices.is_empty()
	hint.text = "请选择" if not visible_choices.is_empty() else "点击 / 空格推进　·　滚轮↑ 历史　·　Esc 菜单"
	for option in visible_choices:
		var b := _button(str(option["label"]), choose.bind(option))
		b.custom_minimum_size = Vector2(960, 52)
		b.add_theme_font_size_override("font_size", 21)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		choice_box.add_child(b)
	# 续玩存档改为去抖写入：每页同步写盘是自动推进卡顿的主因
	resume_dirty = true
	_progress_changed()
	_schedule_auto()

func _unlock_art(node_id: String) -> void:
	var entry: Variant = art_index.get(node_id)
	if entry is Dictionary:
		for key in entry.get("arts", []):
			if not profile["unlocked"].has(key):
				profile["unlocked"][key] = true
				_progress_changed()

func _trace_flow(node_id: String) -> void:
	var owner: Dictionary = flow_data.get("owner", {})
	var block_id := str(owner.get(node_id, ""))
	if block_id == "":
		return
	profile["flow_seen"][block_id] = true
	if checkpoint_flow != block_id:
		# 每个场景块首次进入时保存检查点（含首块），供分支树回溯
		checkpoint_flow = block_id
		profile["checkpoints"][block_id] = _save_data(true)
		_progress_changed()
	active_flow = block_id

func _flow_rewind(block_id: String) -> void:
	if not profile["checkpoints"].has(block_id):
		return
	var snapshot: Dictionary = profile["checkpoints"][block_id].duplicate(true)
	auto_mode = false
	skip_held = false
	skip_active = false
	_update_playback_buttons()
	_apply_snapshot(snapshot)

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
	if in_title or _is_modal():
		return
	auto_timer.stop()
	skip_active = false
	_update_playback_buttons()
	for key in option.get("set", {}):
		flags[key] = option["set"][key]
	current = {}
	_goto(str(option["next"]))
	_show_next()

func advance() -> void:
	if in_title or _is_modal() or finished:
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
	auto_timer.stop()
	body_label.visible_characters = -1
	speaker_label.visible = false
	body_label.text = "—— 全篇到这里暂告一段落 ——"
	hint.text = "分支树与图库可回看已走过的路 · Esc 菜单"
	choice_box.visible = false
	_update_pulse()
	var b := _button("回到标题", _menu.bind("back_title"))
	b.custom_minimum_size = Vector2(960, 52)
	choice_box.add_child(b)
	choice_box.visible = true

# ---------------------------------------------------------------- 自动播放 / 快进

func _auto_tick() -> void:
	advance()

func _is_skipping() -> bool:
	return skip_held or skip_active

func _schedule_auto() -> void:
	auto_timer.stop()
	_update_pulse()
	if in_title or _is_modal() or finished or ui_hidden:
		return
	if _is_skipping():
		# 文本快进：补完文字后高速推进；遇选项自动停下（选项不由快进代答）
		if current_was_read or skip_mode == "all":
			if typewriter_active:
				_complete_typing()
			if not current.get("choices", []).is_empty():
				return
			auto_timer.start(0.09)
		else:
			hint.text = "未读文本 · 已暂停快进（设置中切换为「全部跳过」可继续）"
		return
	if typewriter_active or not current.get("choices", []).is_empty():
		return
	if auto_mode:
		auto_timer.start(_page_delay())

func _page_delay() -> float:
	return maxf(0.35, maxf(2.2, float(typewriter_text.length()) * 0.12) / playback_speed)

func _set_speed(value: float) -> void:
	playback_speed = clampf(value, 1.0, 8.0)
	profile["speed"] = playback_speed
	_progress_changed()
	_update_playback_buttons()
	_schedule_auto()

func _set_text_speed(value: float) -> void:
	text_speed = clampf(value, 10.0, 90.0)
	profile["text_speed"] = text_speed
	if typewriter_timer != null:
		typewriter_timer.wait_time = 1.0 / text_speed
	_progress_changed()

func _set_typewriter(enabled: bool) -> void:
	typewriter_enabled = enabled
	profile["typewriter"] = enabled
	if not enabled and typewriter_active:
		_complete_typing()
	_progress_changed()

func _set_volume(value: float) -> void:
	profile["volume"] = clampf(value, 0.0, 1.0)
	bgm.set_level(float(profile["volume"]))
	_progress_changed()

func _set_dialogue_size(value: int) -> void:
	dialogue_size = clampi(value, 20, 40)
	profile["dialogue_size"] = dialogue_size
	if body_label != null:
		body_label.add_theme_font_size_override("normal_font_size", dialogue_size)
	_progress_changed()

func _set_skip_mode(mode: String) -> void:
	skip_mode = "all" if mode == "all" else "read"
	profile["skip_mode"] = skip_mode
	_progress_changed()

func _set_skip_unread(enabled: bool) -> void:
	# 旧接口，兼容保留：true=全部跳过 / false=已读跳过
	_set_skip_mode("all" if enabled else "read")

func _set_display_mode(mode: String) -> void:
	profile["display"] = str(mode)
	_progress_changed()
	_apply_display_mode()

func _apply_display_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := str(profile.get("display", "window"))
	if mode == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var parts := mode.split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		var size := Vector2i(int(parts[0]), int(parts[1]))
		DisplayServer.window_set_size(size)
		var screen := DisplayServer.window_get_current_screen()
		var screen_pos := DisplayServer.screen_get_position(screen)
		var screen_size := DisplayServer.screen_get_size(screen)
		DisplayServer.window_set_position(screen_pos + (screen_size - size) / 2)

# ---------------------------------------------------------------- 打字机

func _typewriter_tick() -> void:
	if not typewriter_active:
		typewriter_timer.stop()
		return
	if in_title or _is_modal() or ui_hidden or finished:
		return
	typewriter_index += maxi(1, int(playback_speed)) if auto_mode else 1
	body_label.visible_characters = mini(typewriter_index, typewriter_text.length())
	if typewriter_index >= typewriter_text.length():
		_complete_typing()

func _complete_typing() -> void:
	typewriter_active = false
	typewriter_timer.stop()
	body_label.text = typewriter_text
	body_label.visible_characters = -1
	_schedule_auto()

# ---------------------------------------------------------------- 音乐

func _music(cue: String, outro: String = "") -> void:
	if cue == "":
		return
	if bgm.play(cue, outro):
		music_name = bgm.current_id

# ---------------------------------------------------------------- 存读档与进度

func _save_data(include_backlog: bool = false) -> Dictionary:
	var payload := {
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
	if include_backlog:
		payload["backlog"] = backlog.duplicate(true)
	return payload

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
	return saved is Dictionary and saved.get("version") == SAVE_VERSION and _resolve_saved_node(saved) != ""

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
		var valid: bool = saved is Dictionary and saved.get("version") == SAVE_VERSION and _resolve_saved_node(saved) != ""
		var description := "（空）"
		if saved is Dictionary:
			description = "%s · %s\n%s" % [saved.get("chapter", ""), saved.get("title", ""), saved.get("time", "")]
		var b := _button("存档 %d　%s" % [slot, description], _save_slot.bind(slot) if save_mode else _load_slot.bind(slot))
		b.disabled = not save_mode and not valid
		buttons.append([b])
	_open_overlay("保存旅程" if save_mode else "读取旅程", buttons)

func _save_slot(slot: int) -> void:
	_write_json(_slot_path(slot), _save_data(true))
	_close_overlay()

func _load_slot(slot: int) -> void:
	_load_state(_slot_path(slot))

func _resolve_saved_node(saved: Dictionary) -> String:
	# 剧情重编译后节点 id 可能整体变化：优先按 id，失败则按「章节 + 场景标题」
	# 回退到该场景的第一个节点，让旧存档在修订后的剧情里继续可用。
	var node := str(saved.get("node", ""))
	if lookup.has(node):
		return node
	var target_chapter := str(saved.get("chapter", ""))
	var target_title := str(saved.get("title", ""))
	if target_title != "":
		for n in nodes:
			if n.get("type") == "stage" and str(n.get("title", "")) == target_title \
					and (target_chapter == "" or str(n.get("date", "")) == target_chapter):
				return str(n["id"])
	return ""

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
	var node := _resolve_saved_node(saved)
	if node == "":
		push_error("存档指向的剧情节点已不存在: " + str(saved.get("node", "")))
		return
	saved["node"] = node
	_close_overlay()
	_apply_snapshot(saved)

func _apply_snapshot(saved: Dictionary) -> void:
	# 旧存档缺新增 flag 时先按 initial_flags 补默认值，再覆盖已保存的值
	var saved_flags: Dictionary = saved.get("flags", {})
	var merged_flags: Dictionary = data.get("initial_flags", {}).duplicate(true)
	for key in saved_flags:
		merged_flags[key] = saved_flags[key]
	flags = merged_flags
	cast = saved.get("cast", []).duplicate(true)
	bg_id = str(saved.get("bg", "black"))
	cg_id = str(saved.get("cg", ""))
	chapter = str(saved.get("chapter", ""))
	scene_title = str(saved.get("title", ""))
	music_name = str(saved.get("music", ""))
	if saved.has("backlog"):
		backlog = saved["backlog"].duplicate(true)
	if music_name != "":
		_music(music_name)
	hud.get_node("Header").text = _header_caption()
	finished = false
	in_title = false
	ui_hidden = false
	title_screen.visible = false
	hud.visible = true
	choice_box.visible = true
	_goto(str(saved["node"]))
	_show_next()

func _load_profile() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
		if stored is Dictionary and stored.get("version") == 1:
			for key in ["unlocked", "read", "flow_seen", "checkpoints"]:
				if stored.get(key) is Dictionary:
					profile[key] = stored[key]
			for key in ["speed", "volume", "typewriter", "dialogue_size", "text_speed", "skip_mode", "display"]:
				if stored.has(key):
					profile[key] = stored[key]
			# 旧版「快进跳过未读」开关 → 跳过模式迁移
			if not stored.has("skip_mode") and bool(stored.get("skip_unread", false)):
				profile["skip_mode"] = "all"
	playback_speed = clampf(float(profile.get("speed", 1.0)), 1.0, 8.0)
	typewriter_enabled = bool(profile.get("typewriter", true))
	dialogue_size = clampi(int(profile.get("dialogue_size", 26)), 20, 40)
	text_speed = clampf(float(profile.get("text_speed", 45.0)), 10.0, 90.0)
	skip_mode = "all" if str(profile.get("skip_mode", "read")) == "all" else "read"
	profile["skip_mode"] = skip_mode
	# 剧情重编译后场景块 id 会变：清掉已失效的「已走过」记录，避免分支树
	# 出现「已完成 13 / 9」这类计数虚高；检查点同样清理，救得回的按标题迁移。
	var block_ids := {}
	for b in flow_data.get("blocks", []):
		block_ids[str(b["id"])] = true
	for block_id in profile["flow_seen"].keys():
		if not block_ids.has(block_id):
			profile["flow_seen"].erase(block_id)
	for block_id in profile["checkpoints"].keys():
		if not block_ids.has(block_id):
			profile["checkpoints"].erase(block_id)
			continue
		var snapshot: Dictionary = profile["checkpoints"][block_id]
		var rescued := _resolve_saved_node(snapshot)
		if rescued == "":
			profile["checkpoints"].erase(block_id)
		elif rescued != str(snapshot.get("node", "")):
			snapshot["node"] = rescued

func _progress_changed() -> void:
	progress_dirty = true
	if progress_timer != null:
		progress_timer.start()

func _flush_profile() -> void:
	if not progress_dirty:
		return
	_write_json(PROFILE_PATH, profile)
	# 续玩存档随进度一起落盘（去抖后统一写入，避免每页一次磁盘 IO）
	if resume_dirty and not in_title and not str(current.get("id", "")).is_empty():
		_write_json(RESUME_PATH, _save_data())
		resume_dirty = false
	progress_dirty = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_profile()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		skip_held = false
		skip_active = false
		_update_playback_buttons()
		_schedule_auto()

func _exit_tree() -> void:
	_flush_profile()

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
		if event.keycode == KEY_H and not in_title and not _is_modal():
			_hide_ui(not ui_hidden)
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_SPACE, KEY_ENTER]:
			advance()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _is_modal():
				if modal_open:
					_close_overlay()
				else:
					extras.close()
			elif not in_title:
				_game_menu()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not in_title and not _is_modal():
			if ui_hidden:
				_hide_ui(false)
			else:
				advance()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not in_title and not _is_modal():
			# 右键：隐藏/呼出对话界面（面板关闭走 Extras 与 overlay 各自的右键处理）
			_hide_ui(not ui_hidden)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and not in_title and not _is_modal():
			# 滚轮上：直接翻出历史对话
			extras.open("backlog")
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not in_title and not _is_modal():
			# 滚轮下：等价一次空格（打字中先补完，再推一页）
			advance()
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_CTRL and not event.echo:
		skip_held = event.pressed
		_schedule_auto()
		if skip_held:
			get_viewport().set_input_as_handled()

func _hide_ui(hidden: bool) -> void:
	ui_hidden = hidden
	hud.visible = not hidden
	_update_pulse()

func _update_pulse() -> void:
	# 页面读完、无选项、非自动/快进/弹窗时显示推进箭头
	if pulse_label == null:
		return
	var show := not in_title and not _is_modal() and not finished and not ui_hidden \
			and not auto_mode and not _is_skipping() and not current.is_empty()
	pulse_label.visible = show and not typewriter_active and current.get("choices", []).is_empty()

## 对话框边框角标：左上蓝 L、右下黄绿 L（参考图样式）
class FrameAccent extends Control:
	func _draw() -> void:
		var blue := Color("4a86ff")
		var lime := Color("c8f000")
		draw_line(Vector2(1, 26), Vector2(1, 1), blue, 2.0)
		draw_line(Vector2(1, 1), Vector2(30, 1), blue, 2.0)
		draw_line(Vector2(size.x - 1, size.y - 26), Vector2(size.x - 1, size.y - 1), lime, 2.0)
		draw_line(Vector2(size.x - 30, size.y - 1), Vector2(size.x - 1, size.y - 1), lime, 2.0)

# ---------------------------------------------------------------- 冒烟测试
## godot --headless --path . -- --smoke
## 两个分支各跑一遍 + 存读档往返 + 各附加面板开关，必须全部无错。

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
			var visible: Array = _visible_choices(current)
			if not visible.is_empty():
				var index: int = min(smoke_branch, visible.size() - 1)
				choose(visible[index])
			else:
				advance()
		print("SMOKE pass branch=%d pages=%d visited=%d finished=%s" % [branch, pages, visited.size(), str(finished)])
		if not finished:
			all_ok = false
	# 分支树 checkpoint：5 个场景块都应有检查点
	if profile["checkpoints"].size() < 5:
		all_ok = false
		print("SMOKE 分支树检查点不足: %d" % profile["checkpoints"].size())
	# 分支树回溯：从检查点恢复到场景开头并继续推进
	if not profile["checkpoints"].is_empty():
		var block_id: String = profile["checkpoints"].keys()[0]
		var rewind_node := str(profile["checkpoints"][block_id].get("node", ""))
		_flow_rewind(block_id)
		await get_tree().process_frame
		if in_title or current.is_empty() or str(current.get("id", "")) != rewind_node:
			all_ok = false
			print("SMOKE 分支树回溯失败: %s -> %s (current=%s)" % [block_id, rewind_node, str(current.get("id", ""))])
		else:
			print("SMOKE 分支树回溯成功: %s -> %s" % [block_id, rewind_node])
	# 终章路由：条件选项（C 需八枚石板齐全），C 路线须独立收束
	if lookup.has("c13_finale_choice"):
		flags = data.get("initial_flags", {}).duplicate(true)
		_goto("c13_finale_choice")
		current = {}
		_show_next()
		var locked: Array = _visible_choices(current)
		if str(current.get("id", "")) != "c13_finale_choice" or locked.size() != 2:
			all_ok = false
			print("SMOKE 终章路由失败: 石板不齐时应只显示 A/B（实际 %d 个选项）" % locked.size())
		for i in range(1, 9):
			flags["relic_%d" % i] = true
		_show_next()
		var unlocked: Array = _visible_choices(current)
		if unlocked.size() != 3:
			all_ok = false
			print("SMOKE 终章路由失败: 八枚齐全时应显示 A/B/C（实际 %d 个选项）" % unlocked.size())
		else:
			choose(unlocked[2])
			await get_tree().process_frame
			if str(current.get("id", "")) != "c13_ending_c":
				all_ok = false
				print("SMOKE 终章路由失败: C 选项未进入结局 C（当前 %s）" % str(current.get("id", "")))
			var guard_c := 0
			while not finished and guard_c < 20000:
				guard_c += 1
				await get_tree().process_frame
				if finished:
					break
				if typewriter_active:
					_complete_typing()
				if current.is_empty() or not current.get("choices", []).is_empty():
					continue
				advance()
			if not finished:
				all_ok = false
				print("SMOKE 终章路由失败: 结局 C 未能收束")
			else:
				print("SMOKE 终章路由成功: C 路线独立收束")
	else:
		all_ok = false
		print("SMOKE 缺少终章路由节点 c13_finale_choice")
	# 设置项
	_set_speed(4.0)
	_set_text_speed(90.0)
	_set_dialogue_size(30)
	_set_skip_mode("all")
	_set_display_mode("window")
	if playback_speed != 4.0 or dialogue_size != 30 or skip_mode != "all" or text_speed != 90.0:
		all_ok = false
		print("SMOKE 设置项未生效")
	_set_speed(1.0)
	_set_text_speed(45.0)
	_set_dialogue_size(26)
	_set_skip_mode("read")
	# 附加面板：逐个打开再关闭，确保不崩溃
	for view in ["gallery", "flowchart", "backlog", "settings"]:
		extras.open(view)
		await get_tree().process_frame
		if not extras.visible:
			all_ok = false
			print("SMOKE 面板打开失败: " + view)
		extras.close()
		await get_tree().process_frame
	print("SMOKE unlocked_art=%d read=%d flow_seen=%d checkpoints=%d" % [profile["unlocked"].size(), profile["read"].size(), profile["flow_seen"].size(), profile["checkpoints"].size()])
	if profile["unlocked"].is_empty() or profile["read"].is_empty() or profile["flow_seen"].is_empty():
		all_ok = false
		print("SMOKE 进度数据没有记录（图库/分支树会是空的）")
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

## UI 截图调试：Godot --path . -- --shots（输出到 SHOTS_DIR，默认 user://shots）
## 依次截取标题 / 对话页 / 设置 / 分支树，供美术排查用，不参与剧情流程。
func _run_shots() -> void:
	var dir := OS.get_environment("SHOTS_DIR")
	if dir.is_empty():
		dir = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/1_title.png")
	start()
	for i in range(6):
		if typewriter_active:
			_complete_typing()
		if not current.is_empty() and not current.get("choices", []).is_empty():
			choose(_visible_choices(current)[0])
		else:
			advance()
		await get_tree().process_frame
	if typewriter_active:
		_complete_typing()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/2_dialogue.png")
	extras.open("settings")
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/3_settings.png")
	extras.close()
	extras.open("flowchart")
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/4_flowchart.png")
	extras.close()
	# 锁定态预览：临时只把前 4 块记为已走过，截完立即恢复（不落盘）
	var saved_seen: Dictionary = profile["flow_seen"].duplicate(true)
	var saved_active: String = active_flow
	profile["flow_seen"] = {"c01": true, "c06": true, "c07": true, "c08": true}
	active_flow = "c08"
	extras.open("flowchart")
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/5_flowchart_locked.png")
	profile["flow_seen"] = saved_seen
	active_flow = saved_active
	extras.close()
	print("SHOTS saved to " + dir)
	get_tree().quit(0)
