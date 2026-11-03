extends Control
## 设定档案（DLC）：势力 / 人物 / 事件线 三标签 + 人物关系图谱。
## 数据来自 data/dlc.json（tools/build_dlc.py 从剧情知识库编译，构建期产出）。
## 人物详情页复用 assets/sprites 的官方立绘；与「文本集」面板互跳（game.textset）。

const DLC_PATH := "res://data/dlc.json"

const FACTION_COLORS := {
	"白巫女": "e8d8a8", "白教·守护者": "c9b8dd", "白教": "a8c4e8",
	"不死骑士团": "8fa8b8", "王之盾": "d8e0ec", "暗部": "6a7488",
	"魔术协会": "b8a8e0", "国家魔术师团": "88c8a8", "古老民族": "c88888",
	"边陲之国王室": "d8b888", "边陲之国民众": "9aa5b8", "污秽": "c86070", "未明": "5f6c80",
}

var game: Node  # Main
var data: Dictionary = {}

var root: Control
var panel: PanelContainer
var title_label: Label
var tabs_box: HBoxContainer
var tab_buttons: Dictionary = {}  # tab id -> Button
var body: Control
var graph_view: Control          # GraphView.gd 实例
var tooltip: PanelContainer
var tooltip_label: Label

var current_tab := "concepts"    # concepts | entities | events
var current_kind := "list"       # list | detail | graph
var current_entry: Dictionary = {}


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
	panel.custom_minimum_size = Vector2(1140, 700)
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
	title_label = Label.new()
	title_label.text = "设定档案"
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color("eef3fa"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close_b := _button("关闭 (Esc)")
	close_b.pressed.connect(close)
	head.add_child(close_b)
	tabs_box = HBoxContainer.new()
	tabs_box.add_theme_constant_override("separation", 8)
	box.add_child(tabs_box)
	for tab in [["concepts", "势力"], ["entities", "人物"], ["events", "事件线"]]:
		var tb := _button(str(tab[1]))
		tb.toggle_mode = true
		tb.custom_minimum_size = Vector2(120, 34)
		tb.pressed.connect(_switch_tab.bind(str(tab[0])))
		tabs_box.add_child(tb)
		tab_buttons[str(tab[0])] = tb
	body = Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	# 悬停 tooltip（图谱用）
	tooltip = PanelContainer.new()
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = Color("101828f2")
	tstyle.border_color = Color("2e6bffaa")
	tstyle.set_border_width_all(1)
	tstyle.set_corner_radius_all(8)
	tstyle.content_margin_left = 12
	tstyle.content_margin_right = 12
	tstyle.content_margin_top = 6
	tstyle.content_margin_bottom = 6
	tooltip.add_theme_stylebox_override("panel", tstyle)
	tooltip_label = Label.new()
	tooltip_label.add_theme_font_size_override("font_size", 15)
	tooltip.add_child(tooltip_label)
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.z_index = 10
	root.add_child(tooltip)
	if FileAccess.file_exists(DLC_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DLC_PATH))
		if parsed is Dictionary:
			data = parsed
	if data.is_empty():
		title_label.text = "设定档案（数据缺失：运行 tools/build_dlc.py 生成 data/dlc.json）"


func open(tab: String = "") -> void:
	visible = true
	if tab != "":
		current_tab = tab
	current_kind = "list"
	current_entry = {}
	_refresh_tabs()
	_show_list()


func open_entity(entity_id: String) -> void:
	# 供「文本集」互跳：直接进人物详情
	visible = true
	current_tab = "entities"
	current_kind = "detail"
	for e in data.get("entities", []):
		if str(e.get("id")) == entity_id:
			current_entry = e
	_refresh_tabs()
	_show_detail()
	if game != null and game.has_method("_hide_ui"):
		pass


func close() -> void:
	visible = false
	tooltip.visible = false


func _switch_tab(tab: String) -> void:
	current_tab = tab
	current_kind = "list"
	current_entry = {}
	_refresh_tabs()
	_show_list()


func _refresh_tabs() -> void:
	for id in tab_buttons:
		var tb: Button = tab_buttons[id]
		tb.set_pressed_no_signal(id == current_tab)
		tb.add_theme_color_override("font_color",
			Color(COL_LIME if id == current_tab else "c9d4e4"))


const COL_LIME := "c8f000"


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", Color("c9d4e4"))
	b.add_theme_color_override("font_hover_color", Color("f2f6fc"))
	b.add_theme_color_override("font_pressed_color", Color(COL_LIME))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("141b2ae6")
	normal.border_color = Color("2c3650")
	normal.border_width_left = 3
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover := normal.duplicate()
	hover.border_color = Color("2e6bff")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover.duplicate())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	graph_view = null
	tooltip.visible = false


# ------------------------------------------------------------ 列表视图

func _show_list() -> void:
	_clear_body()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	if current_tab == "concepts":
		title_label.text = "设定档案 · 势力"
		for c in data.get("concepts", []):
			list.add_child(_entry_button(str(c.get("title")), str(c.get("summary")), c))
	elif current_tab == "entities":
		title_label.text = "设定档案 · 人物"
		var gbtn := _button("◈ 人物关系图谱（悬停看隶属势力，点击进详情）")
		gbtn.custom_minimum_size = Vector2(0, 40)
		gbtn.pressed.connect(_show_graph)
		list.add_child(gbtn)
		for e in data.get("entities", []):
			var faction: String = str(e.get("faction", ""))
			list.add_child(_entry_button(str(e.get("title")), "〔%s〕%s" % [faction, str(e.get("summary"))], e))
	elif current_tab == "events":
		title_label.text = "设定档案 · 事件线"
		var hint := Label.new()
		hint.text = "按「事件时间线」七纪排序；标注※的为时间待确认（原典无绝对纪年，顺序为推定）"
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color("5f6c80"))
		list.add_child(hint)
		for era in data.get("timeline", []):
			var era_label := Label.new()
			era_label.text = "◆ %s" % str(era.get("era"))
			era_label.add_theme_font_size_override("font_size", 19)
			era_label.add_theme_color_override("font_color", Color("7d93b5"))
			list.add_child(era_label)
			for it in era.get("items", []):
				var ev_title: String = str(it.get("event", ""))
				var text := str(it.get("text"))
				if text.length() > 64:
					text = text.substr(0, 64) + "…"
				if ev_title != "" and data.get("events", []).any(func(ev): return str(ev.get("title")) == ev_title):
					var mark := "※ " if bool(it.get("uncertain")) else ""
					list.add_child(_entry_button(mark + ev_title, text, {"_event_title": ev_title}))
				else:
					var line := Label.new()
					line.text = ("　· " if not bool(it.get("uncertain")) else "　※ ") + text
					line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					line.add_theme_font_size_override("font_size", 15)
					line.add_theme_color_override("font_color", Color("9aa5b8") if not bool(it.get("uncertain")) else Color("6a7488"))
					list.add_child(line)


func _entry_button(title: String, subtitle: String, entry: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 54)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var margin := StyleBoxFlat.new()
	margin.bg_color = Color("10182800")
	margin.content_margin_left = 12
	margin.content_margin_right = 12
	margin.content_margin_top = 6
	margin.content_margin_bottom = 6
	var hov := margin.duplicate()
	hov.bg_color = Color("16223ae6")
	hov.border_color = Color("2e6bff")
	b.add_theme_stylebox_override("normal", margin)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", Color("e8edf6"))
	vb.add_child(t)
	if subtitle != "":
		var s := Label.new()
		s.text = subtitle
		s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		s.add_theme_font_size_override("font_size", 13)
		s.add_theme_color_override("font_color", Color("6a7488"))
		vb.add_child(s)
	b.add_child(vb)
	b.pressed.connect(_open_entry.bind(entry))
	return b


func _open_entry(entry: Dictionary) -> void:
	if entry.has("_event_title"):
		for ev in data.get("events", []):
			if str(ev.get("title")) == str(entry["_event_title"]):
				current_entry = ev
				break
	else:
		current_entry = entry
	current_kind = "detail"
	_show_detail()


# ------------------------------------------------------------ 详情视图

func _show_detail() -> void:
	_clear_body()
	var e := current_entry
	title_label.text = "设定档案 · %s" % str(e.get("title"))
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	body.add_child(vbox)
	var back := _button("← 返回列表")
	back.custom_minimum_size = Vector2(140, 34)
	back.pressed.connect(func():
		current_kind = "list"
		current_entry = {}
		_show_list())
	vbox.add_child(back)
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 18)
	vbox.add_child(hbox)

	# 左：官方立绘（有对应引擎角色时）
	var engine_id := str(e.get("engine_id", ""))
	var has_sprite := engine_id != "" and ResourceLoader.exists("res://assets/sprites/%s/normal.png" % engine_id)
	if has_sprite:
		var sprite_box := VBoxContainer.new()
		sprite_box.custom_minimum_size = Vector2(280, 0)
		hbox.add_child(sprite_box)
		var tex := TextureRect.new()
		tex.texture = load("res://assets/sprites/%s/normal.png" % engine_id)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sprite_box.add_child(tex)
		var fac := Label.new()
		fac.text = "隶属：%s" % str(e.get("faction", "未明"))
		fac.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fac.add_theme_font_size_override("font_size", 15)
		fac.add_theme_color_override("font_color", Color(_faction_color(str(e.get("faction", "")))))
		sprite_box.add_child(fac)

	# 右：正文
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(scroll)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.custom_minimum_size = Vector2(560, 0)
	rtl.add_theme_font_size_override("normal_font_size", 17)
	rtl.add_theme_font_size_override("bold_font_size", 18)
	scroll.add_child(rtl)
	rtl.text = _detail_bbcode(e)


func _detail_bbcode(e: Dictionary) -> String:
	var out := ""
	var title: String = str(e.get("title"))
	out += "[b][font_size=26][color=#eef3fa]%s[/color][/font_size][/b]\n" % _esc(title)
	var faction: String = str(e.get("faction", ""))
	if faction != "":
		out += "[color=%s]◈ 隶属势力：%s[/color]\n" % [_faction_color(faction), _esc(faction)]
	out += "\n"
	for b in e.get("blocks", []):
		match str(b.get("t")):
			"h2":
				out += "\n[b][color=#7d93b5]◆ %s[/color][/b]\n" % _esc(str(b.get("text")))
			"p":
				out += "%s\n\n" % _esc(str(b.get("text")))
			"quote":
				for line in b.get("lines", []):
					out += "[i][color=#8a94ab]▎ %s[/color][/i]\n" % _esc(str(line))
				out += "\n"
			"li":
				out += "[color=#c9d4e4]• %s[/color]\n" % _esc(str(b.get("text")))
			"table":
				for row in b.get("rows", []):
					out += "[color=#9aa5b8]%s[/color]\n" % _esc(" ｜ ".join(row))
				out += "\n"
	# 相关人物 chips（实体）
	var rels: Array = e.get("relations", [])
	if not rels.is_empty():
		out += "\n[b][color=#7d93b5]◆ 相关人物[/color][/b]（点击关系图谱可看连线）\n"
		for r in rels:
			out += "[color=#c9d4e4]• %s —— %s[/color]\n" % [_esc(str(r.get("target"))), _esc(str(r.get("label")))]
	# 与文本集互跳
	var tids: Array = e.get("text_entry_ids", [])
	if not tids.is_empty() and game != null and game.get("textset") != null:
		out += "\n[b][color=#7d93b5]◆ 文本集[/color][/b]\n"
		out += "[i][color=#6a7488]（本人物在「文本集」中的台词与记忆条目可从文本集面板查看）[/color][/i]\n"
	return out


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _faction_color(faction: String) -> String:
	return str(FACTION_COLORS.get(faction, "8fa0b8"))


# ------------------------------------------------------------ 关系图谱

func _show_graph() -> void:
	_clear_body()
	title_label.text = "设定档案 · 人物关系图谱"
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	body.add_child(vbox)
	var top := HBoxContainer.new()
	vbox.add_child(top)
	var back := _button("← 返回人物列表")
	back.custom_minimum_size = Vector2(150, 34)
	back.pressed.connect(func():
		current_kind = "list"
		_show_list())
	top.add_child(back)
	var hint := Label.new()
	hint.text = "拖拽平移 · 滚轮缩放 · 悬停人物查看隶属势力 · 点击人物进入详情"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("6a7488"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(hint)

	graph_view = load("res://GraphView.gd").new()
	graph_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(graph_view)
	var g: Dictionary = data.get("graph", {})
	var colors: Dictionary = {}
	for f in g.get("factions", []):
		colors[str(f)] = Color(_faction_color(str(f)))
	graph_view.setup(g.get("nodes", []), g.get("edges", []), colors, game.character_map)
	graph_view.node_clicked.connect(_on_graph_node_clicked)
	graph_view.hover_changed.connect(_on_graph_hover)


func _on_graph_node_clicked(title: String) -> void:
	for e in data.get("entities", []):
		if str(e.get("title")) == title:
			current_entry = e
			current_kind = "detail"
			_show_detail()
			return


func _on_graph_hover(info: Dictionary, screen_pos: Vector2) -> void:
	if info.is_empty():
		tooltip.visible = false
		return
	tooltip_label.text = "%s\n隶属：%s" % [str(info.get("title")), str(info.get("faction"))]
	tooltip.visible = true
	# 图谱内坐标 → root 坐标（tooltip 挂在 root 上）
	var local := body.global_position + screen_pos
	var tp := local + Vector2(16, 12)
	var margin := 8.0
	var max_x := root.size.x - tooltip.size.x - margin
	var max_y := root.size.y - tooltip.size.y - margin
	tooltip.position = Vector2(min(tp.x, max_x), min(tp.y, max_y))
