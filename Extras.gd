extends Control
## 附加界面：旅途图库 / 剧情分支树 / 旅途回看 / 游戏设置。
## 由 Main.gd 创建并挂载；面板打开时 Main.modal_open 由 Main 统一管理。
##
## v0.5：参考图风格 —— 分区标题（蓝色斜标+渐延长线）、滑杆（黄绿填充+菱形滑块）、
## 胶囊开关、黄绿描边下拉框；分支树改为一行三列网格；右键单击关闭面板（返回）。

var game: Node  # Main

var root: Control          # 全屏遮罩层
var panel: PanelContainer
var title_label: Label
var content: Control       # 当前视图容器
var thumbs: Dictionary = {}  # 缓存缩略图

const CATEGORY_NAMES := {"cg": "事件 CG", "background": "背景", "sprite": "立绘"}
const BLOCK_SIZE := Vector2(300, 140)
const BLOCK_GAP := Vector2(40, 48)
const BLOCK_COLS := 3


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	visible = false
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color("050810d9")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			close())
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1080, 680)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0c1218f7")
	style.border_color = Color("2e6bff80")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 24
	style.shadow_offset = Vector2(0, 6)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 18
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color("eef3fa"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close_b := _button("关闭 (Esc)")
	close_b.pressed.connect(close)
	head.add_child(close_b)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content)

func _input(event: InputEvent) -> void:
	# 右键单击返回：附加面板打开时任意位置右键即关闭
	if visible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close()
		get_viewport().set_input_as_handled()

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", Color("c9d4e4"))
	b.add_theme_color_override("font_hover_color", Color("f2f6fc"))
	b.add_theme_color_override("font_pressed_color", Color("c8f000"))
	b.add_theme_color_override("font_disabled_color", Color("5c6674"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("141b2ae6")
	normal.border_color = Color("2c3650")
	normal.border_width_left = 3
	normal.set_border_width_all(1)
	normal.border_width_left = 3
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("1c2639f2")
	hover.border_color = Color("7d93b5")
	b.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("22304a")
	pressed.border_color = Color("c8f000")
	b.add_theme_stylebox_override("pressed", pressed)
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
	# 淡入过渡
	root.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(root, "modulate:a", 1.0, 0.12)

func close() -> void:
	visible = false

# ---------------------------------------------------------------- 通用小部件

## 分区标题：蓝色竖标 + 标题 + 渐延长线（参考图「▎系统 ——」样式）
func _section(title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var mark := ColorRect.new()
	mark.color = Color("2e6bff")
	mark.custom_minimum_size = Vector2(4, 20)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("eef3fa"))
	row.add_child(label)
	var line := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color("2e6bffaa"), Color("2e6bff00")])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 2
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	line.texture = tex
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	return row

## 设置行首的标签（固定列宽对齐）
func _row_label(text: String, width: float = 118.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("c9d4e4"))
	l.custom_minimum_size = Vector2(width, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

## 滑杆行：标签 + 滑杆 + 当前置值（黄绿小字，参考图样式）
func _slider_row(parent: Control, label_text: String, min_v: float, max_v: float, step: float,
		value: float, setter: Callable, fmt: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	row.add_child(_row_label(label_text))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 22)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color("161d2c")
	groove.border_color = Color("2a3448")
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(2)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("c8f000")
	fill.set_corner_radius_all(2)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", game._diamond_texture(18, Color("101828"), Color("c8f000")))
	s.add_theme_icon_override("grabber_highlight", game._diamond_texture(18, Color("c8f000"), Color("f4ffd0")))
	col.add_child(s)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", Color("c8f000"))
	val.text = str(fmt.call(value))
	col.add_child(val)
	s.value_changed.connect(func(v: float):
		setter.call(v)
		val.text = str(fmt.call(v)))

## 胶囊开关（参考图样式：开=黄绿、关=暗灰，旋钮滑动过渡）
class SwitchButton extends Button:
	var knob: Panel
	func _init() -> void:
		toggle_mode = true
		custom_minimum_size = Vector2(58, 26)
		focus_mode = Control.FOCUS_NONE
		var off := StyleBoxFlat.new()
		off.bg_color = Color("1a2130")
		off.border_color = Color("3a4458")
		off.set_border_width_all(1)
		off.set_corner_radius_all(13)
		var on := off.duplicate()
		on.bg_color = Color("c8f000")
		on.border_color = Color("c8f000")
		add_theme_stylebox_override("normal", off)
		add_theme_stylebox_override("hover", off.duplicate())
		add_theme_stylebox_override("pressed", on)
		add_theme_stylebox_override("hover_pressed", on)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		knob = Panel.new()
		knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color("8a94a6")
		ks.set_corner_radius_all(10)
		knob.add_theme_stylebox_override("panel", ks)
		add_child(knob)
		toggled.connect(func(_on: bool): _sync(true))
		resized.connect(func(): _sync(false))
	func _sync(animate: bool) -> void:
		if knob == null:
			return
		var target_x := size.x - 23.0 if button_pressed else 3.0
		if animate and is_inside_tree():
			create_tween().tween_property(knob, "position:x", target_x, 0.12)
		else:
			knob.position = Vector2(target_x, 3.0)
		var ks: StyleBoxFlat = knob.get_theme_stylebox("panel")
		ks.bg_color = Color("101828") if button_pressed else Color("8a94a6")
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and knob != null:
			_sync(false)

func _toggle_switch(initial: bool, on_toggle: Callable) -> SwitchButton:
	var sw := SwitchButton.new()
	sw.button_pressed = initial
	sw.toggled.connect(on_toggle)
	return sw

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
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	if unlocked:
		style.border_color = Color("2e6bffaa")
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 2)
	else:
		style.border_color = Color("232c3c88")
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
## 一行三列网格排布（参考图卡片观感）；绿蓝连线表示两端都走过的边。

func _build_flowchart() -> void:
	var flow: Dictionary = game.flow_data
	var blocks: Array = flow.get("blocks", [])
	if blocks.is_empty():
		content.add_child(_label("（flowchart.json 为空：请先编译剧情）"))
		return
	var seen: Dictionary = game.profile["flow_seen"]
	# 网格重排：覆盖编译器输出的长条坐标（一行三列，观感饱满）
	var rows := int(ceil(blocks.size() / float(BLOCK_COLS)))
	var canvas_width := 24.0 + BLOCK_COLS * BLOCK_SIZE.x + (BLOCK_COLS - 1) * BLOCK_GAP.x + 24.0
	var canvas_height := 24.0 + rows * BLOCK_SIZE.y + (rows - 1) * BLOCK_GAP.y + 24.0
	for i in range(blocks.size()):
		var block: Dictionary = blocks[i]
		block["x"] = 24.0 + (i % BLOCK_COLS) * (BLOCK_SIZE.x + BLOCK_GAP.x)
		block["y"] = 24.0 + float(i / BLOCK_COLS) * (BLOCK_SIZE.y + BLOCK_GAP.y)
	var summary := _label("已完成 %d / %d 个场景　·　点击已完成的场景可从该处回溯" % [seen.size(), blocks.size()])
	summary.add_theme_font_size_override("font_size", 15)
	summary.add_theme_color_override("font_color", Color("8a94a6"))
	content.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var canvas := Control.new()
	canvas.custom_minimum_size = Vector2(canvas_width, canvas_height)
	scroll.add_child(canvas)
	var edges := FlowEdges.new()
	edges.blocks = blocks
	edges.seen = seen
	edges.block_size = BLOCK_SIZE
	edges.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(edges)
	for b in blocks:
		var block: Dictionary = b
		var btn := Button.new()
		var is_seen: bool = seen.has(str(block["id"]))
		var is_current: bool = str(game.active_flow) == str(block["id"]) and is_seen
		var can_enter: bool = is_seen and game.profile["checkpoints"].has(str(block["id"]))
		if is_seen:
			btn.text = "%s\n%d 页 · 已完成%s" % [block.get("title", block.get("id", "?")), block.get("pages", 0), "（当前所在）" if is_current else ""]
		else:
			btn.text = "？？？\n未解锁"
		btn.position = Vector2(float(block.get("x", 0)), float(block.get("y", 0)))
		btn.size = BLOCK_SIZE
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = not can_enter
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_enter else Control.CURSOR_ARROW
		btn.add_theme_font_size_override("font_size", 16)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var normal := StyleBoxFlat.new()
		normal.set_corner_radius_all(10)
		normal.set_border_width_all(1)
		normal.content_margin_left = 14
		normal.content_margin_right = 14
		if is_current:
			normal.bg_color = Color("16223ccc")
			normal.border_color = Color("c8f000")
		elif is_seen:
			normal.bg_color = Color("101a30ee")
			normal.border_color = Color("3a6cffcc")
			normal.shadow_color = Color(0, 0, 0, 0.35)
			normal.shadow_size = 6
			normal.shadow_offset = Vector2(0, 2)
		else:
			# 未解锁：灰暗锁定样式，按钮直接禁用不可点
			normal.bg_color = Color("0a0e16b4")
			normal.border_color = Color("20283a")
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("disabled", normal.duplicate())
		var hover := normal.duplicate()
		hover.border_color = Color("c8f000") if can_enter else normal.border_color
		btn.add_theme_stylebox_override("hover", hover)
		var font_col := Color("eef3fa") if is_seen else Color("4d5666")
		btn.add_theme_color_override("font_color", font_col)
		btn.add_theme_color_override("font_disabled_color", font_col)
		btn.add_theme_color_override("font_hover_color", Color("ffffff") if can_enter else font_col)
		btn.pressed.connect(func(): _block_clicked(str(block["id"]), is_seen))
		canvas.add_child(btn)

class FlowEdges extends Control:
	var blocks: Array = []
	var seen: Dictionary = {}
	var block_size := Vector2(300, 140)
	func _draw() -> void:
		var by_id := {}
		for b in blocks:
			by_id[str(b["id"])] = b
		for b in blocks:
			for e in b.get("edges", []):
				var to = by_id.get(str(e["to"]))
				if to == null:
					continue
				var fp := Vector2(float(b["x"]), float(b["y"]))
				var tp := Vector2(float(to["x"]), float(to["y"]))
				var col: Color = Color("4a7dff") if seen.has(str(b["id"])) and seen.has(str(e["to"])) else Color("26314a")
				# 横向顺序连接走左右边中点；换行走上下边中点
				var from_pt: Vector2
				var to_pt: Vector2
				if tp.x > fp.x:
					from_pt = fp + Vector2(block_size.x, block_size.y * 0.5)
					to_pt = tp + Vector2(0, block_size.y * 0.5)
				else:
					from_pt = fp + Vector2(block_size.x * 0.5, block_size.y)
					to_pt = tp + Vector2(block_size.x * 0.5, 0)
				draw_line(from_pt, to_pt, col, 2.0)
				var dir := (to_pt - from_pt).normalized()
				draw_line(to_pt - dir * 10.0 + dir.rotated(2.5) * 6.0, to_pt, col, 2.0)
				draw_line(to_pt - dir * 10.0 - dir.rotated(2.5) * 6.0, to_pt, col, 2.0)

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
		line.add_theme_color_override("font_color", Color("8a94a6") if who == "" else Color("dfe6f0"))
		box.add_child(line)
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

# ---------------------------------------------------------------- 设置
## 两列布局（参考图）：左=系统/音频，右=对话/关于；滑杆连续可调。

func _build_settings() -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	content.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	columns.add_child(left)
	columns.add_child(right)

	# ---- 左列：系统 ----
	left.add_child(_section("系统"))
	var disp_row := HBoxContainer.new()
	disp_row.add_theme_constant_override("separation", 14)
	left.add_child(disp_row)
	disp_row.add_child(_row_label("画面尺寸"))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var options := [["fullscreen", "全屏"], ["2560x1440", "2560 × 1440"], ["1920x1080", "1920 × 1080"], ["window", "窗口 · 1280 × 720"]]
	var current_idx := 0
	for i in range(options.size()):
		ob.add_item(options[i][1])
		ob.set_item_metadata(i, options[i][0])
		if str(game.profile.get("display", "window")) == options[i][0]:
			current_idx = i
	ob.selected = current_idx
	var ob_style := StyleBoxFlat.new()
	ob_style.bg_color = Color("131a28e8")
	ob_style.border_color = Color("c8f000aa")
	ob_style.set_border_width_all(1)
	ob_style.set_corner_radius_all(6)
	ob_style.content_margin_left = 12
	ob_style.content_margin_right = 12
	ob_style.content_margin_top = 5
	ob_style.content_margin_bottom = 5
	ob.add_theme_stylebox_override("normal", ob_style)
	var ob_hover := ob_style.duplicate()
	ob_hover.bg_color = Color("1c2639f2")
	ob.add_theme_stylebox_override("hover", ob_hover)
	ob.add_theme_stylebox_override("pressed", ob_hover)
	ob.add_theme_stylebox_override("focus", ob_style.duplicate())
	ob.add_theme_color_override("font_color", Color("c8f000"))
	ob.add_theme_color_override("font_hover_color", Color("e8ff7a"))
	ob.add_theme_color_override("font_pressed_color", Color("e8ff7a"))
	var popup := ob.get_popup()
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color("0e1420f7")
	popup_style.border_color = Color("2e6bffaa")
	popup_style.set_border_width_all(1)
	popup_style.set_corner_radius_all(8)
	popup_style.content_margin_top = 6
	popup_style.content_margin_bottom = 6
	popup.add_theme_stylebox_override("panel", popup_style)
	popup.add_theme_color_override("font_color", Color("c9d4e4"))
	popup.add_theme_color_override("font_hover_color", Color("c8f000"))
	ob.item_selected.connect(func(idx: int): game._set_display_mode(str(ob.get_item_metadata(idx))))
	disp_row.add_child(ob)

	left.add_child(_section("音频"))
	_slider_row(left, "音乐音量", 0.0, 1.0, 0.05, float(game.profile.get("volume", 0.8)),
		func(v: float): game._set_volume(v),
		func(v: float): return "%d%%" % roundi(v * 100))

	# ---- 右列：对话 ----
	right.add_child(_section("对话"))
	_slider_row(right, "对话字号", 20, 40, 1, float(game.dialogue_size),
		func(v: float): game._set_dialogue_size(int(v)),
		func(v: float): return "%d px" % int(v))
	_slider_row(right, "文字速度", 10, 90, 5, game.text_speed,
		func(v: float): game._set_text_speed(v),
		func(v: float): return "%d 字/秒" % int(v))
	_slider_row(right, "自动前进速度", 1.0, 8.0, 0.5, game.playback_speed,
		func(v: float): game._set_speed(v),
		func(v: float): return "%.1f×" % v)
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 14)
	right.add_child(type_row)
	type_row.add_child(_row_label("逐字显示"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(spacer)
	type_row.add_child(_toggle_switch(game.typewriter_enabled, func(on: bool): game._set_typewriter(on)))
	var skip_row := HBoxContainer.new()
	skip_row.add_theme_constant_override("separation", 10)
	right.add_child(skip_row)
	skip_row.add_child(_row_label("跳过模式", 118))
	var group := ButtonGroup.new()
	for entry in [["read", "已读跳过"], ["all", "全部跳过"]]:
		var b := _button(entry[1])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = game.skip_mode == entry[0]
		b.pressed.connect(func(): game._set_skip_mode(entry[0]))
		skip_row.add_child(b)

	# 操作提示：用撑满的占位把它压到面板最底部
	var note := _label("操作：点击 / 空格 / 滚轮↓ 推进 · 滚轮↑ 打开历史 · Ctrl 或「快进」跳过文本（遇选项自动停下）· 右键返回 · H 隐藏界面")
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color("5f6c80"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(bottom_spacer)
	content.add_child(note)

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("c9d4e4"))
	return l
