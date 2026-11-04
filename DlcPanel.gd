extends Control
## 设定档案（DLC）：势力 / 人物 / 事件线 三标签 + 人物关系图谱。
## 数据来自 data/dlc.json（tools/build_dlc.py 从剧情知识库编译，构建期产出）。
## 人物详情页复用 assets/sprites 的官方立绘；与「文本集」面板互跳（game.textset）。
##
## v0.9 交互：列表不再显示介绍文字（详情/悬浮卡片查看）；势力卡图为程序化
## 绘制的黑白红纹章、人物卡图用现有立绘；右键返回（详情/图谱→列表，列表→关闭）。

const DLC_PATH := "res://data/dlc.json"

# 黑白红基调下不再按势力分色：统一白/灰阶（红只用于悬停与强调）
const FACTION_COLORS := {}

# 列表中隐藏的势力子项（需求：删除「舞台与地点」「遗物与宝具」）
const HIDDEN_CONCEPTS := ["舞台与地点", "遗物与宝具"]

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
var hover_card: PanelContainer   # 悬浮卡片（势力/人物）
var card_image_box: Control      # 卡片图区（人物=TextureRect / 势力=FactionEmblem）
var card_name: Label
var card_sub: Label
var card_summary: Label

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
	panel.custom_minimum_size = Vector2(1140, 700)
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
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	title_label = Label.new()
	title_label.text = "设定档案"
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color("f2f2f4"))
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
	tstyle.bg_color = Color("121216f2")
	tstyle.border_color = Color("c23b44aa")
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
	# 悬浮卡片：悬停势力/人物条目时浮出（图 + 名称 + 摘要）
	hover_card = PanelContainer.new()
	var hstyle := StyleBoxFlat.new()
	hstyle.bg_color = Color("0e0e11f7")
	hstyle.border_color = Color("c23b44aa")
	hstyle.set_border_width_all(1)
	hstyle.set_corner_radius_all(10)
	hstyle.shadow_color = Color(0, 0, 0, 0.55)
	hstyle.shadow_size = 14
	hstyle.shadow_offset = Vector2(0, 5)
	hstyle.content_margin_left = 12
	hstyle.content_margin_right = 12
	hstyle.content_margin_top = 10
	hstyle.content_margin_bottom = 12
	hover_card.add_theme_stylebox_override("panel", hstyle)
	hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_card.visible = false
	hover_card.z_index = 12
	root.add_child(hover_card)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_card.add_child(hv)
	card_image_box = Control.new()
	card_image_box.custom_minimum_size = Vector2(252, 168)
	card_image_box.clip_contents = true
	card_image_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(card_image_box)
	card_name = Label.new()
	card_name.add_theme_font_size_override("font_size", 18)
	card_name.add_theme_color_override("font_color", Color("f2f2f4"))
	card_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(card_name)
	card_sub = Label.new()
	card_sub.add_theme_font_size_override("font_size", 13)
	card_sub.add_theme_color_override("font_color", Color("c23b44"))
	card_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(card_sub)
	card_summary = Label.new()
	card_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_summary.custom_minimum_size = Vector2(252, 0)
	card_summary.add_theme_font_size_override("font_size", 13)
	card_summary.add_theme_color_override("font_color", Color("a6a6ae"))
	card_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(card_summary)
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
	_hide_card()


func _input(event: InputEvent) -> void:
	# 右键返回：详情/图谱视图回到列表，列表视图关闭面板（调试截图模式锁输入）。
	# 图谱区域内的右键留给 GraphView 做「复位视图」，不在此拦截。
	if game.debug_shots or not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if graph_view != null and graph_view.is_visible_in_tree() \
				and Rect2(graph_view.get_global_position(), graph_view.size).has_point(event.position):
			return
		if current_kind != "list":
			current_kind = "list"
			current_entry = {}
			_show_list()
		else:
			close()
		get_viewport().set_input_as_handled()


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
			Color(COL_RED_BRIGHT if id == current_tab else "d2d2d8"))


const COL_LIME := "c23b44"
const COL_RED_BRIGHT := "ff5a62"


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", Color("d2d2d8"))
	b.add_theme_color_override("font_hover_color", Color("ffffff"))
	b.add_theme_color_override("font_pressed_color", Color(COL_LIME))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("16161ae6")
	normal.border_color = Color("35353d")
	normal.border_width_left = 3
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover := normal.duplicate()
	hover.border_color = Color("c23b44")
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
	_hide_card()


# ------------------------------------------------------------ 列表视图

func _show_list() -> void:
	_clear_body()
	_hide_card()
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
			# 隐藏子项不进列表；列表条目只显示名称，介绍统一进详情/悬浮卡片
			if str(c.get("title")) in HIDDEN_CONCEPTS:
				continue
			list.add_child(_entry_button(str(c.get("title")), "", c))
	elif current_tab == "entities":
		title_label.text = "设定档案 · 人物"
		var gbtn := _button("◈ 人物关系图谱（悬停看隶属势力，点击进详情）")
		gbtn.custom_minimum_size = Vector2(0, 40)
		gbtn.pressed.connect(_show_graph)
		list.add_child(gbtn)
		for e in data.get("entities", []):
			var faction: String = str(e.get("faction", ""))
			list.add_child(_entry_button(str(e.get("title")), "〔%s〕" % faction if faction != "" else "", e))
	elif current_tab == "events":
		title_label.text = "设定档案 · 事件线"
		var hint := Label.new()
		hint.text = "按「事件时间线」七纪排序；标注※的为时间待确认（原典无绝对纪年，顺序为推定）"
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color("5f5f68"))
		list.add_child(hint)
		for era in data.get("timeline", []):
			var era_label := Label.new()
			era_label.text = "◆ %s" % str(era.get("era"))
			era_label.add_theme_font_size_override("font_size", 19)
			era_label.add_theme_color_override("font_color", Color("8a8a94"))
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
					line.add_theme_color_override("font_color", Color("a6a6ae") if not bool(it.get("uncertain")) else Color("6a6a72"))
					list.add_child(line)


func _entry_button(title: String, subtitle: String, entry: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 54)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var margin := StyleBoxFlat.new()
	margin.bg_color = Color("10101400")
	margin.content_margin_left = 12
	margin.content_margin_right = 12
	margin.content_margin_top = 6
	margin.content_margin_bottom = 6
	var hov := margin.duplicate()
	hov.bg_color = Color("1e1e24e6")
	hov.border_color = Color("c23b44")
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
	t.add_theme_color_override("font_color", Color("eceff0"))
	vb.add_child(t)
	if subtitle != "":
		var s := Label.new()
		s.text = subtitle
		s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		s.add_theme_font_size_override("font_size", 13)
		s.add_theme_color_override("font_color", Color("6a6a72"))
		vb.add_child(s)
	b.add_child(vb)
	b.pressed.connect(_open_entry.bind(entry))
	# 悬停浮出卡片（势力=纹章图 / 人物=立绘图）
	b.mouse_entered.connect(func(): _show_card(entry, b))
	b.mouse_exited.connect(_hide_card)
	return b


# ------------------------------------------------------------ 悬浮卡片

func _show_card(entry: Dictionary, anchor: Control = null) -> void:
	var is_entity := current_tab == "entities" and not entry.has("_event_title")
	var title := str(entry.get("title", ""))
	if title == "":
		return
	# 图区：人物用现有立绘；势力用程序化绘制的黑白红纹章图
	for child in card_image_box.get_children():
		child.queue_free()
	var sub := ""
	if is_entity:
		var e: Dictionary = entry
		sub = "〔%s〕" % str(e.get("faction", "")) if str(e.get("faction", "")) != "" else ""
		var tex := _entity_portrait(e)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_image_box.add_child(tr)
		else:
			card_image_box.add_child(_make_emblem(title))
	else:
		sub = "势力"
		card_image_box.add_child(_make_emblem(title))
	var summary := str(entry.get("summary", ""))
	if summary.length() > 120:
		summary = summary.substr(0, 120) + "…"
	card_name.text = title
	card_sub.text = sub
	card_sub.visible = sub != ""
	card_summary.text = summary
	card_summary.visible = summary != ""
	hover_card.visible = true
	hover_card.reset_size()
	# 定位：条目右侧浮出；靠右溢出翻到左侧；纵向夹在面板内
	var origin := anchor.get_global_rect().position - root.global_position if anchor != null \
			else root.get_local_mouse_position()
	var pos := origin + Vector2(360.0, -10.0)
	if pos.x + hover_card.size.x > root.size.x - 14.0:
		pos.x = maxf(14.0, origin.x - hover_card.size.x - 14.0)
	pos.y = clampf(origin.y, 14.0, maxf(14.0, root.size.y - hover_card.size.y - 14.0))
	hover_card.position = pos

func _hide_card() -> void:
	if hover_card != null:
		hover_card.visible = false

func _entity_portrait(e: Dictionary) -> Texture2D:
	var engine_id := str(e.get("engine_id", ""))
	if engine_id == "":
		return null
	var path := "res://assets/sprites/%s/normal.png" % engine_id
	if not (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
		return null
	return load(path)

func _make_emblem(seed_text: String) -> Control:
	var emblem := FactionEmblem.new()
	emblem.seed_text = seed_text
	emblem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return emblem

## 调试截图用：按列表索引直接触发卡片（等同真实悬停路径）
func debug_hover_card(index: int) -> void:
	var items: Array = data.get("entities", []) if current_tab == "entities" else data.get("concepts", [])
	if index >= items.size():
		return
	_show_card(items[index], null)


## 势力纹章图：黑底 + 白双线边框 + 红色几何纹章（按名称 hash 变化图案），黑白红基调
class FactionEmblem extends Control:
	var seed_text := ""
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := Vector2(w / 2.0, h / 2.0)
		draw_rect(Rect2(0, 0, w, h), Color("0d0d10"))
		draw_rect(Rect2(6, 6, w - 12, h - 12), Color("4a4a54"), false, 1.0)
		draw_rect(Rect2(12, 12, w - 24, h - 24), Color("8a8a94"), false, 1.0)
		var red := Color("c23b44")
		var r := minf(w, h) * 0.24
		var variant := absi(hash(seed_text)) % 3
		draw_arc(c, r, 0, TAU, 64, red, 2.0)
		draw_arc(c, r * 0.8, 0, TAU, 64, Color(red, 0.45), 1.0)
		match variant:
			0:  # 内接菱形
				draw_line(c + Vector2(0, -r * 0.55), c + Vector2(r * 0.55, 0), red, 2.0)
				draw_line(c + Vector2(r * 0.55, 0), c + Vector2(0, r * 0.55), red, 2.0)
				draw_line(c + Vector2(0, r * 0.55), c + Vector2(-r * 0.55, 0), red, 2.0)
				draw_line(c + Vector2(-r * 0.55, 0), c + Vector2(0, -r * 0.55), red, 2.0)
			1:  # 三重尖塔
				for i in range(3):
					var x := c.x + float(i - 1) * r * 0.38
					var top := r * 0.55 if i == 1 else r * 0.32
					draw_line(Vector2(x, c.y + r * 0.5), Vector2(x, c.y - top), red, 2.0)
					draw_circle(Vector2(x, c.y - top), 2.5, red)
			2:  # 交叉双剑
				draw_line(c + Vector2(-r * 0.5, -r * 0.5), c + Vector2(r * 0.5, r * 0.5), red, 2.0)
				draw_line(c + Vector2(r * 0.5, -r * 0.5), c + Vector2(-r * 0.5, r * 0.5), red, 2.0)
				draw_circle(c, 3.5, red)
		draw_line(Vector2(w * 0.22, h - 24), Vector2(w * 0.78, h - 24), Color("8a8a94"), 1.0)
		draw_circle(Vector2(w / 2.0, h - 24), 3.0, red)


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
	out += "[b][font_size=26][color=#f2f2f4]%s[/color][/font_size][/b]\n" % _esc(title)
	var faction: String = str(e.get("faction", ""))
	if faction != "":
		out += "[color=%s]◈ 隶属势力：%s[/color]\n" % [_faction_color(faction), _esc(faction)]
	out += "\n"
	for b in e.get("blocks", []):
		match str(b.get("t")):
			"h2":
				out += "\n[b][color=#a6a6ae]◆ %s[/color][/b]\n" % _esc(str(b.get("text")))
			"p":
				out += "%s\n\n" % _esc(str(b.get("text")))
			"quote":
				for line in b.get("lines", []):
					out += "[i][color=#9a9aa2]▎ %s[/color][/i]\n" % _esc(str(line))
				out += "\n"
			"li":
				out += "[color=#d2d2d8]• %s[/color]\n" % _esc(str(b.get("text")))
			"table":
				for row in b.get("rows", []):
					out += "[color=#a6a6ae]%s[/color]\n" % _esc(" ｜ ".join(row))
				out += "\n"
	# 相关人物 chips（实体）
	var rels: Array = e.get("relations", [])
	if not rels.is_empty():
		out += "\n[b][color=#a6a6ae]◆ 相关人物[/color][/b]（点击关系图谱可看连线）\n"
		for r in rels:
			out += "[color=#d2d2d8]• %s —— %s[/color]\n" % [_esc(str(r.get("target"))), _esc(str(r.get("label")))]
	# 与文本集互跳
	var tids: Array = e.get("text_entry_ids", [])
	if not tids.is_empty() and game != null and game.get("textset") != null:
		out += "\n[b][color=#a6a6ae]◆ 文本集[/color][/b]\n"
		out += "[i][color=#8a8a92]（本人物在「文本集」中的台词与记忆条目可从文本集面板查看）[/color][/i]\n"
	return out


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _faction_color(_faction: String) -> String:
	# 黑白红基调：不再按势力分色，统一灰白
	return "b8b8c0"


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
	hint.add_theme_color_override("font_color", Color("6a6a72"))
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
