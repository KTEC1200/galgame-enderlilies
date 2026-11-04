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
var block_card: PanelContainer     # 分支树悬浮卡片
var block_card_img: TextureRect
var block_card_title: Label
var block_card_info: Label

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
	dim.color = Color("060607d9")
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
	style.bg_color = Color("0f0f12f7")
	style.border_color = Color("c23b4480")
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
	title_label.add_theme_color_override("font_color", Color("f2f2f4"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close_b := _button("关闭 (Esc)")
	close_b.pressed.connect(close)
	head.add_child(close_b)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content)
	# 分支树悬浮卡片：悬停块时浮出（背景图 + 场景信息）
	block_card = PanelContainer.new()
	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color("0e0e11f5")
	cstyle.border_color = Color("c23b44aa")
	cstyle.set_border_width_all(1)
	cstyle.set_corner_radius_all(10)
	cstyle.shadow_color = Color(0, 0, 0, 0.5)
	cstyle.shadow_size = 12
	cstyle.shadow_offset = Vector2(0, 4)
	cstyle.content_margin_left = 10
	cstyle.content_margin_right = 10
	cstyle.content_margin_top = 8
	cstyle.content_margin_bottom = 8
	block_card.add_theme_stylebox_override("panel", cstyle)
	block_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block_card.visible = false
	block_card.z_index = 10
	root.add_child(block_card)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 6)
	cbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block_card.add_child(cbox)
	block_card_img = TextureRect.new()
	block_card_img.custom_minimum_size = Vector2(264, 148)
	block_card_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	block_card_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	block_card_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(block_card_img)
	block_card_title = Label.new()
	block_card_title.add_theme_font_size_override("font_size", 16)
	block_card_title.add_theme_color_override("font_color", Color("f2f2f4"))
	block_card_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(block_card_title)
	block_card_info = Label.new()
	block_card_info.add_theme_font_size_override("font_size", 13)
	block_card_info.add_theme_color_override("font_color", Color("a6a6ae"))
	block_card_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(block_card_info)

func _input(event: InputEvent) -> void:
	# 右键单击返回：附加面板打开时任意位置右键即关闭（调试截图模式锁输入）
	if game.debug_shots:
		return
	if visible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close()
		get_viewport().set_input_as_handled()

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", Color("d2d2d8"))
	b.add_theme_color_override("font_hover_color", Color("ffffff"))
	b.add_theme_color_override("font_pressed_color", Color("c23b44"))
	b.add_theme_color_override("font_disabled_color", Color("5e5e66"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("16161ae6")
	normal.border_color = Color("35353d")
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
	hover.bg_color = Color("1e1e24f2")
	hover.border_color = Color("8a8a94")
	b.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("26161a")
	pressed.border_color = Color("c23b44")
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
	mark.color = Color("c23b44")
	mark.custom_minimum_size = Vector2(4, 20)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("f2f2f4"))
	row.add_child(label)
	var line := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color("c23b44aa"), Color("c23b4400")])
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
	l.add_theme_color_override("font_color", Color("d2d2d8"))
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
	groove.bg_color = Color("1a1a20")
	groove.border_color = Color("34343c")
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(2)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("c23b44")
	fill.set_corner_radius_all(2)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", game._diamond_texture(18, Color("141418"), Color("c23b44")))
	s.add_theme_icon_override("grabber_highlight", game._diamond_texture(18, Color("c23b44"), Color("ffb0b4")))
	col.add_child(s)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", Color("c23b44"))
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
		off.bg_color = Color("1c1c22")
		off.border_color = Color("44444e")
		off.set_border_width_all(1)
		off.set_corner_radius_all(13)
		var on := off.duplicate()
		on.bg_color = Color("c23b44")
		on.border_color = Color("c23b44")
		add_theme_stylebox_override("normal", off)
		add_theme_stylebox_override("hover", off.duplicate())
		add_theme_stylebox_override("pressed", on)
		add_theme_stylebox_override("hover_pressed", on)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		knob = Panel.new()
		knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color("8a8a92")
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
		ks.bg_color = Color("141418") if button_pressed else Color("8a8a92")
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
	hint.add_theme_color_override("font_color", Color("5f5f68"))
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
	style.bg_color = Color("101014e6")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	if unlocked:
		style.border_color = Color("c23b44aa")
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 2)
	else:
		style.border_color = Color("2a2a3188")
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
	label.add_theme_color_override("font_color", Color("a6a6ae") if unlocked else Color("5e5e66"))
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
	info.add_theme_color_override("font_color", Color("a6a6ae"))
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
	summary.add_theme_color_override("font_color", Color("8a8a92"))
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
			normal.bg_color = Color("2a1418cc")
			normal.border_color = Color("c23b44")
		elif is_seen:
			normal.bg_color = Color("131318ee")
			normal.border_color = Color("c23b44cc")
			normal.shadow_color = Color(0, 0, 0, 0.35)
			normal.shadow_size = 6
			normal.shadow_offset = Vector2(0, 2)
		else:
			# 未解锁：灰暗锁定样式，按钮直接禁用不可点
			normal.bg_color = Color("0c0c10b4")
			normal.border_color = Color("26262e")
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("disabled", normal.duplicate())
		var hover := normal.duplicate()
		hover.border_color = Color("c23b44") if can_enter else normal.border_color
		btn.add_theme_stylebox_override("hover", hover)
		var font_col := Color("f2f2f4") if is_seen else Color("565660")
		btn.add_theme_color_override("font_color", font_col)
		btn.add_theme_color_override("font_disabled_color", font_col)
		btn.add_theme_color_override("font_hover_color", Color("ffffff") if can_enter else font_col)
		btn.pressed.connect(func(): _block_clicked(str(block["id"]), is_seen))
		btn.mouse_entered.connect(func(): _show_block_card(block, is_seen, btn))
		btn.mouse_exited.connect(_hide_block_card)
		canvas.add_child(btn)

## 分支树悬浮卡片：悬停块浮出对应背景图（未解锁块不剧透，显示锁面）
func _show_block_card(block: Dictionary, is_seen: bool, anchor: Control = null) -> void:
	var title := str(block.get("title", block.get("id", "?")))
	if is_seen:
		var bg_key: String = game._block_bg_key(str(block["id"]))
		block_card_img.texture = game._texture("res://assets/backgrounds/%s.png" % bg_key) if bg_key != "" else null
		block_card_img.modulate = Color.WHITE
		block_card_title.text = title
		var is_current: bool = str(game.active_flow) == str(block["id"])
		block_card_info.text = "%d 页 · 已完成%s" % [block.get("pages", 0), "（当前所在）" if is_current else ""]
	else:
		block_card_img.texture = null
		block_card_img.modulate = Color(0.16, 0.16, 0.18)
		block_card_title.text = "？？？"
		block_card_info.text = "尚未解锁"
	block_card.visible = true
	block_card.reset_size()
	# 定位：默认出现在块右侧；靠右溢出则放左侧；纵向夹在视口内
	var origin := Vector2.ZERO
	if anchor != null:
		origin = anchor.get_global_rect().position - root.global_position
	else:
		origin = root.get_local_mouse_position()
	var pos := origin + Vector2(float(BLOCK_SIZE.x) + 14.0, 0.0)
	if pos.x + block_card.size.x > root.size.x - 12.0:
		pos.x = maxf(12.0, origin.x - block_card.size.x - 14.0)
	pos.y = clampf(origin.y, 12.0, maxf(12.0, root.size.y - block_card.size.y - 12.0))
	block_card.position = pos

func _hide_block_card() -> void:
	block_card.visible = false

## 调试截图用：按块 id 直接触发卡片（等同真实悬停路径）
func debug_hover_block_card(block_id: String) -> void:
	for b in game.flow_data.get("blocks", []):
		if str(b.get("id")) == block_id:
			_show_block_card(b, game.profile["flow_seen"].has(block_id), null)
			return

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
				var col: Color = Color("c23b44") if seen.has(str(b["id"])) and seen.has(str(e["to"])) else Color("3a3a44")
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
## 条目不再逐行带 [章节 · 场景] 方括号前缀：章节编号收进面板标题旁，
## 条目按「章节 · 场景」分组（组变化时插一行小标），行内只留「说话人：文本」。

func _build_backlog() -> void:
	var caption := "旅途回看"
	if str(game.chapter) != "":
		caption += "　·　" + str(game.chapter)
	title_label.text = caption
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var entries: Array = game.backlog
	if entries.is_empty():
		box.add_child(_label("还没有浏览过的对话。"))
	var last_group := ""
	for entry in entries:
		var who: String = entry.get("speaker", "")
		var group: String = "%s · %s" % [entry.get("chapter", ""), entry.get("title", "")]
		if group != last_group:
			last_group = group
			box.add_child(_backlog_group_header(group))
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.text = (who + "：" + str(entry.get("text", ""))) if who != "" else str(entry.get("text", ""))
		line.add_theme_font_size_override("font_size", 16)
		line.add_theme_color_override("font_color", Color("8a8a92") if who == "" else Color("e6e6ea"))
		box.add_child(line)
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _backlog_group_header(text: String) -> Control:
	# 分组小标：红色短标 + 章节场景名 + 渐延长线（无方括号）
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var mark := ColorRect.new()
	mark.color = Color("c23b44")
	mark.custom_minimum_size = Vector2(3, 16)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("a6a6ae"))
	row.add_child(label)
	var line := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color("c23b4466"), Color("c23b4400")])
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
	ob_style.bg_color = Color("15151ae8")
	ob_style.border_color = Color("c23b44aa")
	ob_style.set_border_width_all(1)
	ob_style.set_corner_radius_all(6)
	ob_style.content_margin_left = 12
	ob_style.content_margin_right = 12
	ob_style.content_margin_top = 5
	ob_style.content_margin_bottom = 5
	ob.add_theme_stylebox_override("normal", ob_style)
	var ob_hover := ob_style.duplicate()
	ob_hover.bg_color = Color("1e1e24f2")
	ob.add_theme_stylebox_override("hover", ob_hover)
	ob.add_theme_stylebox_override("pressed", ob_hover)
	ob.add_theme_stylebox_override("focus", ob_style.duplicate())
	ob.add_theme_color_override("font_color", Color("c23b44"))
	ob.add_theme_color_override("font_hover_color", Color("ff5a62"))
	ob.add_theme_color_override("font_pressed_color", Color("ff5a62"))
	var popup := ob.get_popup()
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color("101014f7")
	popup_style.border_color = Color("c23b44aa")
	popup_style.set_border_width_all(1)
	popup_style.set_corner_radius_all(8)
	popup_style.content_margin_top = 6
	popup_style.content_margin_bottom = 6
	popup.add_theme_stylebox_override("panel", popup_style)
	popup.add_theme_color_override("font_color", Color("d2d2d8"))
	popup.add_theme_color_override("font_hover_color", Color("c23b44"))
	ob.item_selected.connect(func(idx: int): game._set_display_mode(str(ob.get_item_metadata(idx))))
	disp_row.add_child(ob)

	left.add_child(_section("音频"))
	_slider_row(left, "音乐音量", 0.0, 1.0, 0.05, float(game.profile.get("volume", 0.8)),
		func(v: float): game._set_volume(v),
		func(v: float): return "%d%%" % roundi(v * 100))

	# ---- 右列：对话 ----
	right.add_child(_section("对话"))
	_slider_row(right, "对话框透明度", 0.15, 1.0, 0.05, float(game.profile.get("dialogue_opacity", 0.93)),
		func(v: float): game._set_dialogue_opacity(v),
		func(v: float): return "%d%%" % roundi(v * 100))
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
	note.add_theme_color_override("font_color", Color("5f5f68"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(bottom_spacer)
	content.add_child(note)

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("d2d2d8"))
	return l
