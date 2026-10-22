class_name UltimateRegistry
extends RefCounted
## The list of available spells. Add new abilities here.


static func create_default() -> Array[UltimateAbility]:
	var list: Array[UltimateAbility] = [
		ManaDischarge.new(), # Fixed to the neutral Spell input.
		NovaBurst.new(),
		SpiritVolley.new(),
		AscendantForm.new(),
		CometDash.new(),
		RepulseAegis.new(),
		StasisField.new(),
		RadiantLance.new(),
		MeteorSlam.new(),
	]
	return list
