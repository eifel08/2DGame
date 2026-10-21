class_name Damage
extends RefCounted
## The three sources of damage to the player. Each follows its own
## invulnerability rule (see HealthEnergy.blocks):
##
##   ENEMY       body contact with a creature (dummies, the boss's charge)
##               -> blocked by i-frames and invulnerability (dash, casts,
##                  dives, recent hits)
##   PROJECTILE  anything fired, by an enemy or by a hazard (shards,
##               shockwaves, a future turret or dripping acid)
##               -> blocked by i-frames and invulnerability, like ENEMY
##   HAZARD      direct contact with the environment (spikes, lava, acid)
##               -> NEVER blocked by i-frames or invulnerability; only the
##                  debug God Mode protects. The player is always moved back
##                  to safe ground, so a damage loop is impossible.
##
## A projectile launched by a hazard is still a PROJECTILE: only touching the
## hazard itself bypasses i-frames.

enum Source { ENEMY, PROJECTILE, HAZARD }
