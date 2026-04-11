## TimelineBar — custom-drawn horizontal timeline visualization.
##
## Shows branch segments colored by direction (red=forward, blue=reverse),
## a moving marker for the current tick, reversal-point markers, and
## direction arrows inside each segment.
extends Control

var timeline_manager = null

const BG_COLOR       := Color(0.08, 0.08, 0.12, 0.85)
const BORDER_COLOR   := Color(0.25, 0.25, 0.3, 0.6)
const FWD_COLOR      := Color(0.82, 0.2, 0.15, 0.65)
const REV_COLOR      := Color(0.18, 0.32, 0.92, 0.65)
const FWD_ACTIVE     := Color(0.92, 0.28, 0.2, 0.9)
const REV_ACTIVE     := Color(0.25, 0.42, 1.0, 0.9)
const COLLAPSED_COLOR := Color(0.3, 0.3, 0.3, 0.25)
const PIVOT_COLOR    := Color(1, 1, 1, 0.35)
const MARKER_COLOR   := Color(1, 1, 1, 1)
const MIN_TICK_RANGE := 120
const MAX_LANES := 5
const SUMMARY_COLOR := Color(0.35, 0.35, 0.4, 0.3)
const SUMMARY_LABEL_COLOR := Color(0.6, 0.6, 0.65, 0.5)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if timeline_manager == null:
		return

	var all_branches: Array = timeline_manager.branches
	var tick: int = timeline_manager.global_tick
	var dir: int = timeline_manager.time_direction

	var w := size.x
	var h := size.y

	# Background + border
	draw_rect(Rect2(0, 0, w, h), BG_COLOR)
	draw_rect(Rect2(0, 0, w, h), BORDER_COLOR, false, 1.0)

	if all_branches.is_empty():
		return

	# ── Compute tick range (always uses ALL branches) ──
	var min_t := tick
	var max_t := tick
	for b in all_branches:
		min_t = mini(min_t, mini(b.start_tick, b.end_tick))
		max_t = maxi(max_t, maxi(b.start_tick, b.end_tick))

	if max_t - min_t < MIN_TICK_RANGE:
		var center := (min_t + max_t) / 2
		min_t = center - MIN_TICK_RANGE / 2
		max_t = center + MIN_TICK_RANGE / 2

	var pad := maxi(int((max_t - min_t) * 0.05), 5)
	min_t -= pad
	max_t += pad

	# ── Split branches into visible lanes vs summary ──
	var active_idx: int = timeline_manager.active_branch_index
	var n := all_branches.size()
	var visible_indices: Array[int] = []
	var summary_indices: Array[int] = []

	if n <= MAX_LANES:
		for i in range(n):
			visible_indices.append(i)
	else:
		# Always include the active branch. Fill remaining slots with
		# the most recent branches (highest indices).
		var recent_start := n - (MAX_LANES - 1)
		# If active branch is already in the recent set, just use recent.
		if active_idx >= recent_start:
			for i in range(recent_start, n):
				visible_indices.append(i)
		else:
			# Active branch is old — reserve one slot for it.
			visible_indices.append(active_idx)
			var fill_start := n - (MAX_LANES - 2)
			for i in range(fill_start, n):
				visible_indices.append(i)
		# Everything else goes into the summary.
		for i in range(n):
			if visible_indices.find(i) == -1:
				summary_indices.append(i)

	var has_summary := summary_indices.size() > 0
	var display_count: int = visible_indices.size() + (1 if has_summary else 0)

	# ── Lane layout ──
	var gap := 1.0
	var pad_y := 3.0
	var lane_h := (h - 2.0 * pad_y - gap * maxf(display_count - 1, 0)) / float(display_count)
	lane_h = maxf(lane_h, 3.0)

	var lane_idx := 0

	# ── Draw summary lane (older collapsed branches) ──
	if has_summary:
		var first_sb: BranchTrack = all_branches[summary_indices[0]]
		var sum_lo: int = int(first_sb.start_tick)
		var sum_hi: int = sum_lo
		for si in summary_indices:
			var sb: BranchTrack = all_branches[si]
			sum_lo = mini(sum_lo, mini(sb.start_tick, sb.end_tick))
			sum_hi = maxi(sum_hi, maxi(sb.start_tick, sb.end_tick))
		var sx1 := _tx(sum_lo, min_t, max_t, w)
		var sx2 := _tx(sum_hi, min_t, max_t, w)
		var seg_w := maxf(sx2 - sx1, 3.0)
		var sy := pad_y
		draw_rect(Rect2(sx1, sy, seg_w, lane_h), SUMMARY_COLOR)
		# "+N" label
		var label := "+%d" % summary_indices.size()
		var font := ThemeDB.fallback_font
		var fsize := mini(int(lane_h - 1), 10)
		if fsize >= 6:
			draw_string(font, Vector2(sx1 + 3, sy + lane_h - 2), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, SUMMARY_LABEL_COLOR)
		lane_idx = 1

	# ── Draw visible branch segments ──
	for vi in range(visible_indices.size()):
		var i: int = visible_indices[vi]
		var b: BranchTrack = all_branches[i]
		var t_lo := mini(b.start_tick, b.end_tick)
		var t_hi := maxi(b.start_tick, b.end_tick)
		var x1 := _tx(t_lo, min_t, max_t, w)
		var x2 := _tx(t_hi, min_t, max_t, w)
		var seg_w := maxf(x2 - x1, 3.0)
		var y := pad_y + float(lane_idx) * (lane_h + gap)

		var color: Color
		if b.collapsed:
			color = COLLAPSED_COLOR
		elif i == active_idx:
			color = FWD_ACTIVE if b.direction == 1 else REV_ACTIVE
		else:
			color = FWD_COLOR if b.direction == 1 else REV_COLOR

		draw_rect(Rect2(x1, y, seg_w, lane_h), color)

		# Direction chevrons inside the segment
		if seg_w > 14.0 and lane_h > 4.0:
			_draw_chevrons(x1, y, seg_w, lane_h, b.direction, color.lightened(0.25))
		lane_idx += 1

	# ── Reversal (pivot) markers ──
	for b in all_branches:
		if b.sealed:
			var px := _tx(b.end_tick, min_t, max_t, w)
			draw_line(Vector2(px, 1), Vector2(px, h - 1), PIVOT_COLOR, 1.5)

	# ── Current tick marker ──
	var cx := _tx(tick, min_t, max_t, w)
	draw_line(Vector2(cx, 0), Vector2(cx, h), MARKER_COLOR, 2.0)

	# Direction triangle
	var ts := minf(6.0, h * 0.3)
	var mid_y := h / 2.0
	if dir == 1:
		draw_polygon(
			PackedVector2Array([
				Vector2(cx + 3, mid_y - ts),
				Vector2(cx + 3 + ts * 1.4, mid_y),
				Vector2(cx + 3, mid_y + ts),
			]),
			PackedColorArray([MARKER_COLOR, MARKER_COLOR, MARKER_COLOR])
		)
	else:
		draw_polygon(
			PackedVector2Array([
				Vector2(cx - 3, mid_y - ts),
				Vector2(cx - 3 - ts * 1.4, mid_y),
				Vector2(cx - 3, mid_y + ts),
			]),
			PackedColorArray([MARKER_COLOR, MARKER_COLOR, MARKER_COLOR])
		)


func _draw_chevrons(x: float, y: float, seg_w: float, lane_h: float, dir: int, color: Color) -> void:
	var step := 18.0
	var ch := lane_h * 0.28
	var mid_y := y + lane_h / 2.0
	var px := x + 8.0
	var end_x := x + seg_w - 4.0

	while px < end_x:
		if dir == 1:
			draw_line(Vector2(px, mid_y - ch), Vector2(px + 3.5, mid_y), color, 1.0)
			draw_line(Vector2(px + 3.5, mid_y), Vector2(px, mid_y + ch), color, 1.0)
		else:
			draw_line(Vector2(px + 3.5, mid_y - ch), Vector2(px, mid_y), color, 1.0)
			draw_line(Vector2(px, mid_y), Vector2(px + 3.5, mid_y + ch), color, 1.0)
		px += step


func _tx(tick_val: int, min_t: int, max_t: int, width: float) -> float:
	if max_t == min_t:
		return width / 2.0
	return (float(tick_val - min_t) / float(max_t - min_t)) * width
