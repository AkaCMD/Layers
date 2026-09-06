package game

import "core:fmt"
import "core:log"
import "core:strings"

level_load_from_txt :: proc(index: int) -> bool {
	add_player()

	builder := strings.builder_make(context.temp_allocator)

	for layer_index in 0 ..< NUM_LAYERS {
		strings.builder_reset(&builder)
		path := fmt.sbprintf(&builder, "assets/levels/%d-l%d.txt", index, layer_index + 1)
		if data, ok := read_entire_file(path, context.temp_allocator); ok {
			level_load_layer_from_txt(layer_index, string(data))
			log.infof("Loaded level%d layer%d!", index, layer_index + 1)
		} else {
			log.infof("Could't load level%d layer%d!", index, layer_index + 1)
			return false
		}
	}
	return true
}

level_load_layer_from_txt :: proc(layer_index: int, content: string) {
	x := 0
	y := 0

	fmt.printf("\nlayer %d:\n", layer_index + 1)
	for char in content {
		// print the level
		if char != '\n' {
			fmt.printf("%c", char)
		} else {
			fmt.printf("\n")
		}

		// calculate the x, y coordinates
		if char == ' ' {
			x += 1
			continue
		} else if char == '\n' {
			y += 1
			x = -1
			continue
		} else {
			x += 1
		}

		en := new(Entity, context.temp_allocator)
		en.position = {x, y}
		en.layer = layer_index
		switch char {
		case '@':
			setup_player(en)
		case 'C':
			setup_cargo(en)
		case '#':
			setup_wall(en)
		case '*':
			setup_target(en)
		case '>':
			setup_flag(en)
		case:
			continue
		}
		append(&world.entities, en^)
	}
}

add_player :: proc() {
	en: Entity
	setup_player(&en)
	append(&world.entities, en)
}

level_unload :: proc() {
	clear(&world.entities)
	clear(&undo_stack)

	is_completed = false
}

unload_game :: proc() {
	delete(world.entities)
	delete(world.layers)
	delete(undo_stack)
}

level_load_by_index :: proc(index: int) -> bool {
	level_unload()
	if ok := level_load_from_txt(index); ok {
		current_level_index = index
		return true
	} else {
		level_load_from_txt(current_level_index)
		log.warn("Load level failed.")
		return false
	}
}

level_reload :: proc() {
	level_unload()
	level_load_from_txt(current_level_index)
	log.info("reload")
}
