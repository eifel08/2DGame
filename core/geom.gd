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
