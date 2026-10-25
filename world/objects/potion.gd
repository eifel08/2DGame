class_name Potion
extends Relic
## A consumable upgrade lying in the world. Touching it drinks it at once:
##   Health Potion (stat "max_health")  raises max health for good (and heals fully)
##   Mana Potion   (stat "max_energy")  raises max energy for good
## It works like a Relic (WorldState.relics keeps it collected, by relic_id),
## so a drunk potion never comes back. `amount` <= 0 uses the Config default
## (Config.progression.*_potion_amount), read by the game, not here.
## Art: each kind has its own scene (health_potion.tscn: red round flask,
## mana_potion.tscn: blue tall angular bottle). Replace Visual freely.
