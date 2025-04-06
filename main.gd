extends Control

@onready var open_button = $VBoxContainer/OpenFileButton
@onready var save_button = $VBoxContainer/SaveFileButton
@onready var file_dialog = $FileDialog
@onready var fields_container = $VBoxContainer/ScrollContainer/Fields

var current_file_path = ""
var loaded_variant = null

func _ready():
	open_button.pressed.connect(_on_open_pressed)
	save_button.pressed.connect(_on_save_pressed)
	file_dialog.file_selected.connect(_on_file_selected)

func _on_open_pressed():
	file_dialog.popup_centered()

func read_and_decrypt_xor(path: String, key: int = 4) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		push_error("File does not exist: " + path)
		return PackedByteArray()

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open file: " + path)
		return PackedByteArray()

	var raw_bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	# XOR decrypt
	for i in raw_bytes.size():
		raw_bytes[i] = raw_bytes[i] ^ key

	return raw_bytes

func _on_file_selected(path):
	current_file_path = path
	var decrypted_bytes = read_and_decrypt_xor(path, 4)

	var variant = bytes_to_var(decrypted_bytes)
	if variant == null:
		push_error("Failed to parse Variant from data")
		return

	loaded_variant = variant

	# Clear UI
	for child in fields_container.get_children():
		child.queue_free()

	# Display each item if it's a collection, otherwise show one field
	if variant is Array:
		for value in variant:
			_add_variant_field(value)
	elif variant is Dictionary:
		for key in variant.keys():
			_add_variant_field(variant[key], key)
	else:
		_add_variant_field(variant)

func _add_variant_field(value, key = null):
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size.y = 60
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if key != null:
		var key_label = Label.new()
		key_label.text = "Key: " + str(key)
		vbox.add_child(key_label)

	var type_label = Label.new()
	
	type_label.add_theme_color_override("font_color", Color.SKY_BLUE)
	vbox.add_child(type_label)

	var text_edit = TextEdit.new()
	text_edit.text = JSON.stringify(value)
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.custom_minimum_size.y = 40
	vbox.add_child(text_edit)

	fields_container.add_child(vbox)

func _on_save_pressed():
	if current_file_path == "":
		push_error("No file loaded")
		return

	var output_variant

	if loaded_variant is Array:
		var result_array = []
		for container in fields_container.get_children():
			for child in container.get_children():
				if child is TextEdit:
					var value = parse_input_to_variant(child.text)
					if value == null:
						push_error("Failed to parse: " + child.text)
						continue
					result_array.append(value)
		output_variant = result_array

	elif loaded_variant is Dictionary:
		var result_dict = {}
		var index = 0
		for container in fields_container.get_children():
			var key = loaded_variant.keys()[index]
			for child in container.get_children():
				if child is TextEdit:
					var value = parse_input_to_variant(child.text)
					if value == null:
						push_error("Failed to parse: " + child.text)
						continue
					result_dict[key] = value
			index += 1
		output_variant = result_dict

	else:
		# Single value case
		for container in fields_container.get_children():
			for child in container.get_children():
				if child is TextEdit:
					output_variant = parse_input_to_variant(child.text)

	var variant_bytes = var_to_bytes(output_variant)

	# XOR encrypt (make mutable copy)
	var encrypted_bytes = PackedByteArray(variant_bytes)
	for i in encrypted_bytes.size():
		encrypted_bytes[i] ^= 4

	var file = FileAccess.open(current_file_path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open file for writing")
		return

	file.store_buffer(encrypted_bytes)
	file.close()

	print("Saved and encrypted to:", current_file_path)

func parse_input_to_variant(text: String) -> Variant:
	var trimmed = text.strip_edges()

	# Basic types
	if trimmed.is_valid_int():
		return int(trimmed)
	elif trimmed.is_valid_float():
		return float(trimmed)
	elif trimmed.to_lower() == "true":
		return true
	elif trimmed.to_lower() == "false":
		return false

	# JSON (array or dictionary)
	if (trimmed.begins_with("[") and trimmed.ends_with("]")) or (trimmed.begins_with("{") and trimmed.ends_with("}")):
		var json = JSON.new()
		var result = json.parse(trimmed)
		if result == OK:
			return json.get_data()

	# Fallback to string
	return trimmed
