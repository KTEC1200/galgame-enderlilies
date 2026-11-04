extends Control
## 人物关系图谱视图：节点=人物，边=关系；支持拖拽平移 / 滚轮缩放 / 悬停 tooltip / 点击进详情。
## 布局坐标由 build_dlc.py 预计算（0~1 归一化，确定性力导向），本脚本只做视图与交互。

signal node_clicked(title: String)
signal hover_changed(info: Dictionary, screen_pos: Vector2)

const WORLD := Vector2(1700.0, 1050.0)   # 布局世界尺寸
const NODE_R := 13.0

var nodes: Array = []            # [{id,title,faction,x,y}]
var edges: Array = []            # [{a,b,label}]
var colors: Dictionary = {}      # faction -> Color
var name_alias: Dictionary = {}  # 可选：title -> 引擎显示名
var zoom := 1.0
var offset := Vector2(80, 40)    # 世界原点的屏幕位置
var hover_idx := -1
var dragging := false
var drag_moved := false
var press_pos := Vector2.ZERO
var fitted := false             # 首次绘制时自适应视口

@onready var _font: Font = get_theme_default_font()


func setup(node_list: Array, edge_list: Array, faction_colors: Dictionary, aliases: Dictionary = {}) -> void:
	nodes = node_list
	edges = edge_list
	colors = faction_colors
	name_alias = aliases
	zoom = 1.0
	offset = Vector2(60, 40)
	hover_idx = -1
	fitted = false
	queue_redraw()


func _fit_view() -> void:
	# 把整个世界居中放进当前控件（留 6% 边距）
	if size.x < 40 or size.y < 40:
		return
	zoom = min(size.x / WORLD.x, size.y / WORLD.y) * 0.94
	offset = WORLD / 2.0 - size / (2.0 * zoom)
	fitted = true


func _world(i: int) -> Vector2:
	var n: Dictionary = nodes[i]
	return Vector2(float(n.get("x", 0.5)) * WORLD.x, float(n.get("y", 0.5)) * WORLD.y)


func _screen(i: int) -> Vector2:
	return (_world(i) - offset) * zoom


func _node_radius(i: int) -> float:
	# 度数越高（关系越多）节点越大
	var deg := 0
	for e in edges:
		if str(e.get("a")) == str(nodes[i].get("title")) or str(e.get("b")) == str(nodes[i].get("title")):
			deg += 1
	return NODE_R + min(deg, 6) * 1.2


func _draw() -> void:
	if nodes.is_empty():
		var hint := "暂无图谱数据（tools/build_dlc.py）"
		draw_string(_font, Vector2(24, 40), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("6a6a72"))
		return
	if not fitted:
		_fit_view()
	# 边
	for e in edges:
		var ia := _index_of(str(e.get("a")))
		var ib := _index_of(str(e.get("b")))
		if ia < 0 or ib < 0:
			continue
		var highlight := hover_idx == ia or hover_idx == ib
		var col := Color("3a3a44") if not highlight else Color("ff5a62")
		draw_line(_screen(ia), _screen(ib), col, 2.0 if highlight else 1.0)
	# 节点
	for i in range(nodes.size()):
		var p := _screen(i)
		var n: Dictionary = nodes[i]
		var faction: String = str(n.get("faction", ""))
		var base: Color = colors.get(faction, Color("b8b8c0"))
		var r := _node_radius(i)
		if i == hover_idx:
			draw_circle(p, r + 5.0, Color(base, 0.25))
		draw_circle(p, r, Color("141418"))
		draw_arc(p, r, 0.0, TAU, 40, base, 2.5 if i == hover_idx else 1.8)
		# 名字：沿半径向外排布（弦图样式），按方向决定对齐
		var label: String = str(n.get("title"))
		var fs := 14
		var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var center := (WORLD * 0.5 - offset) * zoom
		var radial := p - center
		if radial.length() < 1.0:
			radial = Vector2(0, -1)
		radial = radial.normalized()
		var lp := p + radial * (r + 9.0)
		if radial.x < -0.35:
			lp.x -= ts.x
		elif radial.x <= 0.35:
			lp.x -= ts.x / 2.0
			if radial.y > 0.0:
				lp.y += ts.y * 0.85
		draw_string(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color("f2f2f4") if i == hover_idx else Color("c4c4ca"))


func _index_of(title: String) -> int:
	for i in range(nodes.size()):
		if str(nodes[i].get("title")) == title:
			return i
	return -1


func _hit(pos: Vector2) -> int:
	for i in range(nodes.size()):
		if pos.distance_to(_screen(i)) <= _node_radius(i) + 6.0:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.12)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.12)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				dragging = true
				drag_moved = false
				press_pos = mb.position
			else:
				dragging = false
				var idx := _hit(mb.position)
				if idx >= 0 and not drag_moved:
					node_clicked.emit(str(nodes[idx].get("title")))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# 右键复位
			zoom = 1.0
			offset = Vector2(60, 40)
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging:
			if mm.position.distance_to(press_pos) > 4.0:
				drag_moved = true
			offset -= mm.relative / zoom
			queue_redraw()
			return
		var idx := _hit(mm.position)
		if idx != hover_idx:
			hover_idx = idx
			queue_redraw()
		if idx >= 0:
			hover_changed.emit(nodes[idx], mm.position)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		else:
			hover_changed.emit({}, mm.position)
			mouse_default_cursor_shape = Control.CURSOR_ARROW
	elif event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		dragging = false


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom: float = clamp(zoom * factor, 0.45, 3.2)
	var world := screen_pos / zoom + offset
	zoom = new_zoom
	offset = world - screen_pos / zoom
	queue_redraw()
