extends Control
## 文本集：《ENDER LILIES 文本集》阅读面板。
## 数据来自 data/text_collection.json（tools/build_text_collection.py 编译，跳过对话剧情）。
## 只含三个固定分类：人物和记忆 / 笔记内容 / 遗物；支持标题搜索、分类折叠、
## 与「设定档案」互跳（同名人物）。窄屏时左列表与阅读区切换显示。

const TC_PATH := "res://data/text_collection.json"
const CAT_ORDER := [["characters", "人物和记忆"], ["notes", "笔记内容"], ["relics", "遗物"]]

var game: Node  # Main
var data: Dictionary = {}

var root: Control
var panel: PanelContainer
var body_hbox: HBoxContainer
var list_side: VBoxContainer
var reader_side: VBoxContainer
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var search_box: LineEdit
var reader_title: Label
var reader_rtl: RichTextLabel
var reader_jump: Button
var collapsed := {}            # cat_id -> true 折叠
var current_entry: Dictionary = {}
var current_button: Button
var narrow := false


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
	panel.custom_minimum_size = Vector2(1180, 700)
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
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title_label := Label.new()
	title_label.text = "文本集 · 人物和记忆 / 笔记内容 / 遗物"
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color("eef3fa"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close_b := _button("关闭 (Esc)")
	close_b.pressed.connect(close)
	head.add_child(close_b)

	body_hbox = HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 16)
	box.add_child(body_hbox)

	# ---- 左：搜索 + 分类列表 ----
	list_side = VBoxContainer.new()
	list_side.custom_minimum_size = Vector2(330, 0)
	list_side.add_theme_constant_override("separation", 8)
	body_hbox.add_child(list_side)
	search_box = LineEdit.new()
	search_box.placeholder_text = "搜索标题…"
	search_box.clear_button_enabled = true
	search_box.add_theme_font_size_override("font_size", 16)
	search_box.text_changed.connect(func(_t): _rebuild_list())
	list_side.add_child(search_box)
	list_scroll = ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_side.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 4)
	list_scroll.add_child(list_box)

	# ---- 右：阅读区 ----
	reader_side = VBoxContainer.new()
	reader_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reader_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reader_side.add_theme_constant_override("separation", 8)
	body_hbox.add_child(reader_side)
	var reader_top := HBoxContainer.new()
	reader_side.add_child(reader_top)
	reader_jump = _button("◈ 查看人物档案")
	reader_jump.visible = false
	reader_jump.pressed.connect(_jump_to_entity)
	reader_top.add_child(reader_jump)
	var back_list := _button("← 返回列表")
	back_list.visible = false
	back_list.pressed.connect(_show_list_only)
	reader_top.add_child(back_list)
	reader_title = Label.new()
	reader_title.text = ""
	reader_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reader_title.add_theme_font_size_override("font_size", 24)
	reader_title.add_theme_color_override("font_color", Color("eef3fa"))
	reader_side.add_child(reader_title)
	var reader_scroll := ScrollContainer.new()
	reader_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reader_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reader_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	reader_side.add_child(reader_scroll)
	reader_rtl = RichTextLabel.new()
	reader_rtl.bbcode_enabled = true
	reader_rtl.fit_content = true
	reader_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reader_rtl.custom_minimum_size = Vector2(560, 0)
	reader_rtl.add_theme_font_size_override("normal_font_size", 17)
	reader_scroll.add_child(reader_rtl)

	if FileAccess.file_exists(TC_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TC_PATH))
		if parsed is Dictionary:
			data = parsed


func open() -> void:
	visible = true
	current_entry = {}
	# 默认展示第一个条目，避免右侧空白（先选中再重建列表，让高亮生效）
	var first := _first_entry()
	if not first.is_empty():
		_select(first, null)
	_rebuild_list()
	_apply_layout()


func open_entry(entry_id: String) -> void:
	# 供「设定档案」互跳
	visible = true
	for cat in data.get("categories", []):
		for e in cat.get("entries", []):
			if str(e.get("id")) == entry_id:
				collapsed[str(cat.get("id"))] = false
				_select(e, null)
	_apply_layout()
	_show_reader_only()


func close() -> void:
	visible = false


func _first_entry() -> Dictionary:
	for cat in data.get("categories", []):
		for e in cat.get("entries", []):
			return e
	return {}


func _entries() -> Array:
	var out: Array = []
	for cat in data.get("categories", []):
		for e in cat.get("entries", []):
			out.append({"cat": cat, "entry": e})
	return out


func _rebuild_list() -> void:
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.queue_free()
	current_button = null
	var kw: String = search_box.text.strip_edges()
	for cat in data.get("categories", []):
		var cat_id := str(cat.get("id"))
		var cat_name := str(cat.get("name"))
		var entries: Array = cat.get("entries", [])
		var shown: Array = entries.filter(func(e): return kw == "" or kw in str(e.get("title")))
		if shown.is_empty():
			continue
		var head_b := _button(("▸ " if collapsed.get(cat_id, false) else "▾ ") + cat_name)
		head_b.custom_minimum_size = Vector2(0, 38)
		head_b.add_theme_font_size_override("font_size", 18)
		head_b.add_theme_color_override("font_color", Color("7d93b5"))
		head_b.pressed.connect(func():
			collapsed[cat_id] = not collapsed.get(cat_id, false)
			_rebuild_list())
		list_box.add_child(head_b)
		if collapsed.get(cat_id, false):
			continue
		for e in shown:
			var title: String = str(e.get("title"))
			var b := Button.new()
			b.text = title
			b.focus_mode = Control.FOCUS_NONE
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.add_theme_font_size_override("font_size", 15)
			b.add_theme_color_override("font_color", Color("c9d4e4"))
			b.add_theme_color_override("font_hover_color", Color("f2f6fc"))
			var normal := StyleBoxFlat.new()
			normal.bg_color = Color("10182800")
			normal.content_margin_left = 14
			normal.content_margin_right = 8
			normal.content_margin_top = 5
			normal.content_margin_bottom = 5
			var hov := normal.duplicate()
			hov.bg_color = Color("16223ae6")
			b.add_theme_stylebox_override("normal", normal)
			b.add_theme_stylebox_override("hover", hov)
			b.add_theme_stylebox_override("pressed", hov)
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.pressed.connect(_select.bind(e, b))
			list_box.add_child(b)
			if current_entry.get("id", "") == e.get("id", ""):
				_mark_selected(b)


func _mark_selected(b: Button) -> void:
	if current_button != null:
		current_button.add_theme_color_override("font_color", Color("c9d4e4"))
	current_button = b
	b.add_theme_color_override("font_color", Color("c8f000"))


func _select(entry: Dictionary, button: Button) -> void:
	current_entry = entry
	reader_title.text = str(entry.get("title"))
	reader_rtl.text = _entry_bbcode(entry)
	reader_rtl.get_parent().scroll_vertical = 0   # 切换条目回到顶部
	var has_entity: bool = str(entry.get("entity_id", "")) != "" \
		and game != null and game.get("dlc") != null
	reader_jump.visible = has_entity
	if button != null:
		_mark_selected(button)
	if narrow:
		_show_reader_only()


func _entry_bbcode(e: Dictionary) -> String:
	var out := ""
	var desc: Array = e.get("description", [])
	if not desc.is_empty():
		for line in desc:
			if str(line) == "":
				out += "\n"
			else:
				out += "[i][color=#8a94ab]▎ %s[/color][/i]\n" % _esc(str(line))
		out += "\n"
	for line in e.get("lines", []):
		if str(line) == "":
			out += "\n"
		else:
			out += "%s\n" % _esc(str(line))
	return out


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _jump_to_entity() -> void:
	if game != null and game.get("dlc") != null:
		game.dlc.open_entity(str(current_entry.get("entity_id")))


# ---- 窄屏：列表 / 阅读区切换 ----

func _apply_layout() -> void:
	narrow = panel.size.x < 900 and panel.size.x > 0
	if narrow and not current_entry.is_empty():
		_show_reader_only()
	else:
		_show_list_only()


func _show_list_only() -> void:
	list_side.visible = true
	if narrow:
		reader_side.visible = false
	else:
		reader_side.visible = true


func _show_reader_only() -> void:
	reader_side.visible = true
	if narrow:
		list_side.visible = false


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", Color("c9d4e4"))
	b.add_theme_color_override("font_hover_color", Color("f2f6fc"))
	b.add_theme_color_override("font_pressed_color", Color("c8f000"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("141b2ae6")
	normal.border_color = Color("2c3650")
	normal.border_width_left = 3
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hov := normal.duplicate()
	hov.border_color = Color("2e6bff")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov.duplicate())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b
