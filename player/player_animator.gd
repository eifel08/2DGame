class_name PlayerAnimator
extends Node
## Animation state machine for the player.
## Ordered rules map gameplay state to an animation name; the first match wins.
## Gameplay code never calls play(). To add a state, add a rule here and an
## animation with the same name to the AnimationPlayer's library.
##
## The AnimationPlayer runs in MANUAL mode and is advanced from step(), so
## hitstop freezes animation frames too.

var animation_player: AnimationPlayer
var current := ""
var _rules: Array = []


func setup(p: Player) -> void:
	animation_player = p.get_node("AnimationPlayer")
	_rules = [
		["hurt", func() -> bool: return p.state_name() == "hurt"],
		["cast", func() -> bool: return p.state_name() == "cast"],
		["heal", func() -> bool: return p.state_name() == "heal"],
		["dash", func() -> bool: return p.state_name() == "dash" or p.state_name() == "ability"],
		["attack_up", func() -> bool: return p.attack_dir == "up"],
		["attack_down", func() -> bool: return p.attack_dir == "down"],
		["attack_side", func() -> bool: return p.attack_dir == "left" or p.attack_dir == "right"],
		["wall_slide", func() -> bool: return p.wall_sliding],
		["jump", func() -> bool: return not p.grounded and p.velocity.y < 0.0],
		["fall", func() -> bool: return not p.grounded],
		["run", func() -> bool: return absf(p.velocity.x) > 20.0],
		["idle", func() -> bool: return true],
	]


func resolve() -> String:
	for rule in _rules:
		if rule[1].call():
			return rule[0]
	return "idle"


func step(delta: float) -> void:
	var next := resolve()
	if next != current:
		current = next
		animation_player.play(next)
	animation_player.advance(delta)


func reset() -> void:
	current = ""
