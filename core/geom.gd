class_name Geom
extends RefCounted
## Small geometry helpers shared by combat and abilities.


static func circle_overlaps_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var nearest := Vector2(
		clampf(center.x, rect.position.x, rect.end.x),
		clampf(center.y, rect.position.y, rect.end.y))
	return center.distance_squared_to(nearest) <= radius * radius


## Frame-rate independent smoothing factor for exponential lerps.
static func damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


## Swept box test: how far a box of half size `half`, centered at `from`, can
## move along the unit vector `dir` before it touches `rect`. 0 when they
## already overlap, INF when the box never reaches it.
static func box_cast_distance(from: Vector2, half: Vector2, dir: Vector2, rect: Rect2) -> float:
	var r := rect.grow_individual(half.x, half.y, half.x, half.y)
	if r.has_point(from):
		return 0.0
	var t_enter := -INF
	var t_exit := INF
	for axis in 2:
		var o: float = from[axis]
		var d: float = dir[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(d) < 0.000001:
			if o < lo or o > hi:
				return INF
			continue
		var t1 := (lo - o) / d
		var t2 := (hi - o) / d
		t_enter = maxf(t_enter, minf(t1, t2))
		t_exit = minf(t_exit, maxf(t1, t2))
	if t_exit < maxf(t_enter, 0.0):
		return INF
	return maxf(t_enter, 0.0)
