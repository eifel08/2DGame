class_name FxPlayer
extends Node2D
## Root of every visual effect scene in effects/fx/ (one scene per effect,
## named after it: hit_spark.tscn, boss_dissolve.tscn, ...). Gameplay code
## only asks for an effect by name (Effects.play); what it looks like lives
## entirely in the scene.
##
## On start it plays every child it knows: CPUParticles2D / GPUParticles2D
## (emitting), AnimatedSprite2D (play), AnimationPlayer ("play" clip) and
## AudioStreamPlayer(2D). The placeholders are CPUParticles2D plus simple
## drawn shapes (RingPlaceholder, PortalPlaceholder). To use real art, open
## the scene, delete the placeholder children and add your own: nothing in
## the gameplay code changes. No autoloads here (the generator builds these).

@export var lifetime := 1.0 ## Seconds until the effect frees itself (0 = never).
@export var emit_time := 0.0 ## > 0: continuous particles stop emitting after this.

var time := 0.0


func _ready() -> void:
	for child in get_children():
		if child is CPUParticles2D or child is GPUParticles2D:
			child.restart()
			child.emitting = true
		elif child is AnimatedSprite2D:
			child.play()
		elif child is AnimationPlayer and child.has_animation("play"):
			child.play("play")
		elif child is AudioStreamPlayer or child is AudioStreamPlayer2D:
			child.play()


func _process(delta: float) -> void:
	time += delta
	if emit_time > 0.0 and time >= emit_time:
		emit_time = 0.0
		stop_emitting()
	if lifetime > 0.0 and time >= lifetime:
		queue_free()


func stop_emitting() -> void:
	for child in get_children():
		if child is CPUParticles2D or child is GPUParticles2D:
			child.emitting = false
