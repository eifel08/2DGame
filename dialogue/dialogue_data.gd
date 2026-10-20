class_name DialogueData
extends Resource
## One conversation or lore text: a speaker name and a list of pages.
## Create new ones in the FileSystem dock: right-click > New > Resource > DialogueData.

@export var speaker := ""
@export_multiline var pages: PackedStringArray = []
