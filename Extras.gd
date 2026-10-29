extends Control
## 附加界面：旅途图库 / 剧情分支树 / 旅途回看 / 游戏设置。
## 由 Main.gd 创建并挂载；面板打开时 Main.modal_open 由 Main 统一管理。

var game: Node  # Main

var root: Control          # 全屏遮罩层
var panel: PanelContainer
var title_label: Label
var content: Control       # 当前视图容器
var thumbs: Dictionary = {}  # 缓存缩略图

const CATEGORY_NAMES := {"cg": "事件 CG", "background": "背景", "sprite": "立绘"}
const CANVAS_BLOCK := Vector2(260, 110)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	visible = false
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color("050810cc")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(940, 620)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b111acc")
	style.border_color = Color("46536a99")
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color("dfe6f0"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close_b := _button("关闭 (Esc)")
	close_b.pressed.connect(close)
	head.add_child(close_b)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content)

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", Color("c9d4e4"))
	b.add_theme_color_override("font_hover_color", Color("eef3fa"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("141a24e6")
	normal.border_color = Color("46536a99")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("1d2736f0")
	hover.border_color = Color("7d93b5")
	b.add_theme_stylebox_override("hover", hover)
	return b

func open(view: String) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	match view:
		"gallery":
			title_label.text = "旅途图库"
			_build_gallery()
		"flowchart":
			title_label.text = "剧情分支树"
			_build_flowchart()
		"backlog":
			title_label.text = "旅途回看"
			_build_backlog()
		"settings":
			title_label.text = "游戏设置"
			_build_settings()
	visible = true
	root.modulate = Color.WHITE

func close() -> void:
	visible = false

# ---------------------------------------------------------------- 图库

var gallery_category := "cg"

func _build_gallery() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	for cat in ["cg", "background", "sprite"]:
		var b := _button(CATEGORY_NAMES[cat])
		b.toggle_mode = true
		b.button_pressed = cat == gallery_category
		b.pressed.connect(func():
			gallery_category = cat
			open("gallery"))
		tabs.add_child(b)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("5f6c80"))
	content.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var items: Dictionary = game.gallery_items
	var keys := []
	for key in items:
		if items[key]["category"] == gallery_category:
			keys.append(key)
	keys.sort()
	var unlocked_count := 0
	for key in keys:
		var unlocked: bool = game.profile["unlocked"].has(key)
		if unlocked:
			unlocked_count += 1
		grid.add_child(_gallery_cell(key, items[key], unlocked))
	hint.text = "%s　·　已解锁 %d / %d" % [CATEGORY_NAMES[gallery_category], unlocked_count, keys.size()]

func _gallery_cell(key: String, item: Dictionary, unlocked: bool) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(212, 168)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0e1420e6")
	style.border_color = Color("46536a66") if not unlocked else Color("7d93b5aa")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	cell.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	cell.add_child(box)
	var frame := Button.new()
	frame.custom_minimum_size = Vector2(0, 118)
	frame.focus_mode = Control.FOCUS_NONE
	frame.disabled = not unlocked
	frame.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	frame.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	box.add_child(frame)
	var tex := TextureRect.new()
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture = _thumbnail(key, Vector2(200, 112))
	tex.modulate = Color.WHITE if unlocked else Color(0.10, 0.12, 0.16)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tex)
	if unlocked:
		frame.pressed.connect(func(): _gallery_zoom(key, item))
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("9db4d8") if unlocked else Color("5c6674"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text = item["title"] if unlocked else "？？？"
	box.add_child(label)
	return cell

func _gallery_zoom(key: String, item: Dictionary) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var back := _button("← 返回图库")
	back.pressed.connect(func(): open("gallery"))
	content.add_child(back)
	var tex := TextureRect.new()
	tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture = _thumbnail(key, Vector2(880, 420))
	content.add_child(tex)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color("9db4d8"))
	var places := "　".join(PackedStringArray(item["locations"]))
	info.text = "%s　·　解锁于：%s" % [item["title"], places]
	content.add_child(info)

func _thumbnail(key: String, box: Vector2) -> Texture2D:
	var cache_key := "%s@%dx%d" % [key, int(box.x), int(box.y)]
	if thumbs.has(cache_key):
		return thumbs[cache_key]
	var path := _art_path(key)
	var tex: Texture2D = game._texture(path)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	var factor: float = minf(box.x / maxf(1.0, float(img.get_width())), box.y / maxf(1.0, float(img.get_height())))
	img.resize(maxi(1, int(img.get_width() * factor)), maxi(1, int(img.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	var result := ImageTexture.create_from_image(img)
	thumbs[cache_key] = result
	return result

func _art_path(key: String) -> String:
	var parts := key.split("/")
	match parts[0]:
		"cg":
			return "res://assets/cg/%s.png" % parts[1]
		"background":
			return "res://assets/backgrounds/%s.png" % parts[1]
		"sprite":
			return "res://assets/sprites/%s/%s.png" % [parts[1], parts[2]]
		"chibi":
			return "res://assets/chibi/%s/%s.png" % [parts[1], parts[2]]
	return "res://assets/" + key + ".png"

# ---------------------------------------------------------------- 分支树

func _build_flowchart() -> void:
	var flow: Dictionary = game.flow_data
	var blocks: Array = flow.get("blocks", [])
	if blocks.is_empty():
		content.add_child(_label("（flowchart.json 为空：请先编译剧情）"))
		return
	var seen: Dictionary = game.profile["flow_seen"]
	var summary := _label("已走过 %d / %d 个场景（点击已走过的场景可回溯）" % [seen.size(), blocks.size()])
	content.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var canvas := Control.new()
	canvas.custom_minimum_size = Vector2(float(flow.get("width", 1200)), maxf(float(flow.get("height", 300)), 320.0))
	scroll.add_child(canvas)
	var edges := FlowEdges.new()
	edges.blocks = blocks
	edges.seen = seen
	edges.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(edges)
	for b in blocks:
		var block: Dictionary = b
		var btn := Button.new()
		btn.text = "%s\n%d 页" % [block.get("title", block.get("id", "?")), block.get("pages", 0)]
		btn.position = Vector2(float(block.get("x", 0)), float(block.get("y", 0)))
		btn.size = CANVAS_BLOCK
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 15)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var is_seen: bool = seen.has(str(block["id"]))
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color("16202ecc") if is_seen else Color("0c111acc")
		normal.border_color = Color("9db4d8aa") if is_seen else Color("2c354288")
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(10)
		normal.content_margin_left = 10
		normal.content_margin_right = 10
		btn.add_theme_stylebox_override("normal", normal)
		var hover := normal.duplicate()
		hover.border_color = Color("eef3fa")
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_color_override("font_color", Color("dfe6f0") if is_seen else Color("5c6674"))
		btn.add_theme_color_override("font_hover_color", Color("ffffff"))
		btn.pressed.connect(func(): _block_clicked(str(block["id"]), is_seen))
		canvas.add_child(btn)

class FlowEdges extends Control:
	var blocks: Array = []
	var seen: Dictionary = {}
	func _draw() -> void:
		var by_id := {}
		for b in blocks:
			by_id[str(b["id"])] = b
		for b in blocks:
			for e in b.get("edges", []):
				var to = by_id.get(str(e["to"]))
				if to == null:
					continue
				var from_pt := Vector2(float(b["x"]) + 262.0, float(b["y"]) + 55.0)
				var to_pt := Vector2(float(to["x"]), float(to["y"]) + 55.0)
				var both_seen: bool = seen.has(str(b["id"])) and seen.has(str(e["to"]))
				draw_line(from_pt, to_pt, Color("9db4d8") if both_seen else Color("2a3547"), 2.0)
				# 箭头
				var dir := (to_pt - from_pt).normalized()
				draw_line(to_pt - dir * 10.0 + dir.rotated(2.5) * 6.0, to_pt, Color("9db4d8") if both_seen else Color("2a3547"), 2.0)
				draw_line(to_pt - dir * 10.0 - dir.rotated(2.5) * 6.0, to_pt, Color("9db4d8") if both_seen else Color("2a3547"), 2.0)

func _block_clicked(block_id: String, is_seen: bool) -> void:
	if not is_seen:
		return
	if not game.profile["checkpoints"].has(block_id):
		return
	game._flow_rewind(block_id)
	close()

# ---------------------------------------------------------------- 回看

func _build_backlog() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	var entries: Array = game.backlog
	if entries.is_empty():
		box.add_child(_label("还没有浏览过的对话。"))
	for entry in entries:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var who: String = entry.get("speaker", "")
		var head: String = "[%s · %s] " % [entry.get("chapter", ""), entry.get("title", "")]
		line.text = (head + who + "：" + str(entry.get("text", ""))) if who != "" else (head + str(entry.get("text", "")))
		line.add_theme_font_size_override("font_size", 16)
		line.add_theme_color_override("font_color", Color("aebac9") if who == "" else Color("dfe6f0"))
		box.add_child(line)
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

# ---------------------------------------------------------------- 设置

func _build_settings() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	content.add_child(box)
	# 自动播放倍速
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 10)
	box.add_child(speed_row)
	speed_row.add_child(_label("自动播放倍速"))
	for speed in [1.0, 2.0, 4.0, 8.0]:
		var b := _button("%d×" % int(speed))
		b.toggle_mode = true
		b.button_pressed = game.playback_speed == speed
		b.pressed.connect(func(): game._set_speed(speed))
		speed_row.add_child(b)
	# 打字机
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 10)
	box.add_child(type_row)
	type_row.add_child(_label("逐字显示"))
	var type_b := _button("开" if game.typewriter_enabled else "关")
	type_b.pressed.connect(func():
		game._set_typewriter(not game.typewriter_enabled)
		open("settings"))
	type_row.add_child(type_b)
	# 音量
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	box.add_child(vol_row)
	vol_row.add_child(_label("音乐音量"))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(game.profile.get("volume", 0.8))
	slider.custom_minimum_size = Vector2(280, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float): game._set_volume(v))
	vol_row.add_child(slider)
	var note := _label("提示：Ctrl 快进已读内容，遇未读自动停下；H / 右键隐藏界面。")
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color("5f6c80"))
	box.add_child(note)

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("c9d4e4"))
	return l
