class_name UltimateRegistry
extends RefCounted
## The list of available ultimates. Add new abilities here.


static func create_default() -> Array[UltimateAbility]:
	var list: Array[UltimateAbility] = [
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
