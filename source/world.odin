package game

import "core:log"
import rl "vendor:raylib"

// Number of layers per level. Increase this and add a matching
// `assets/levels/{n}-l{layer}.txt` file to add more layers.
NUM_LAYERS :: 2
// Special layer value for entities that don't belong to any togglable layer
// (the player): always active, always drawn on top.
NO_LAYER :: -1

Entity_Type :: enum u8 {
	Player,
	Cargo,
	Wall,
	Target,
	Flag,
}
// Level Editor Symbols
// Player => '@'
// Cargo => 'C'
// Wall => '#'
// Target => '*'
// Flag => '>'

Layer :: struct {
	is_visible: bool,
	order:      int, // draw order; higher = drawn later (in front)
}

World :: struct {
	entities: [dynamic]Entity,
	layers:   [dynamic]Layer,
}

Entity :: struct {
	type:        Entity_Type,
	texture:     Texture_Name,
	position:    [2]int,
	layer:       int, // index into world.layers, or NO_LAYER
	priority:    int, // start from 0
	can_overlap: bool,
	is_flipped:  bool,
}

Record :: struct {
	world: World,
}

add_entity :: proc(w: ^World, e: Entity) {
	append(&w.entities, e)
}

setup_player :: proc(en: ^Entity) {
	en.texture = .Duck
	en.type = .Player
	en.position = {1, 1}
	en.priority = 3
	en.layer = NO_LAYER
	en.is_flipped = false
}

setup_cargo :: proc(en: ^Entity) {
	en.texture = .Cargo
	en.type = .Cargo
	en.priority = 3
}

setup_wall :: proc(en: ^Entity) {
	en.texture = .Wall
	en.type = .Wall
	en.priority = 3
}

setup_flag :: proc(en: ^Entity) {
	en.texture = .Flag_No
	en.type = .Flag
	en.priority = 2
	en.can_overlap = true
}

setup_target :: proc(en: ^Entity) {
	en.texture = .Target
	en.type = .Target
	en.priority = 2
	en.can_overlap = true
}

init_layers :: proc() {
	clear(&world.layers)
	for i in 0 ..< NUM_LAYERS {
		append(&world.layers, Layer{is_visible = true, order = NUM_LAYERS - 1 - i})
	}
}

clone_world :: proc(w: ^World) -> World {
	nw: World
	nw.layers = make([dynamic]Layer, len(w.layers), arena_allocator)
	copy(nw.layers[:], w.layers[:])
	nw.entities = make([dynamic]Entity, len(w.entities), arena_allocator)
	copy(nw.entities[:], w.entities[:])
	return nw
}

layer_is_active :: proc(layer: int) -> bool {
	if layer < 0 {
		return true
	}
	return layer < len(world.layers) && world.layers[layer].is_visible
}

any_layer_visible :: proc() -> bool {
	for layer in world.layers {
		if layer.is_visible {
			return true
		}
	}
	return false
}

toggle_layer_visibility :: proc(index: int) {
	world.layers[index].is_visible = !world.layers[index].is_visible
	// never allow all layers to be hidden at once
	if !any_layer_visible() {
		for i in 0 ..< len(world.layers) {
			if i != index {
				world.layers[i].is_visible = true
				break
			}
		}
	}
}

move :: proc(en: ^Entity, dir: [2]int) -> bool {
	target_pos := en.position + dir
	if !is_within_bounds(target_pos) {
		return false // Out of bounds, do nothing
	}

	// cargo under the player (same cell) rides along when the player moves
	box: ^Entity = nil
	if en.type == .Player {
		for b in find_blocking_entities_at(en.position, en) {
			if b.type == .Cargo {
				box = b
				break
			}
		}
	}

	blocking := find_blocking_entities_at(target_pos, en)

	if len(blocking) == 0 {
		update_position(en, target_pos, box)
		return true
	}

	// every blocking entity must be a pushable cargo
	for b in blocking {
		if b.type != .Cargo {
			return false
		}
		if !is_within_bounds(b.position + dir) {
			return false
		}
		if len(find_blocking_entities_at(b.position + dir, en)) > 0 {
			return false
		}
	}

	update_position(en, target_pos, box)
	for b in blocking {
		b.position += dir
	}
	rl.PlaySound(sfx_pushbox)
	return true
}

is_within_bounds :: proc(pos: [2]int) -> bool {
	return pos.x >= 0 && pos.x < GRID_COUNT && pos.y >= 0 && pos.y < GRID_COUNT
}

update_position :: proc(en: ^Entity, target_pos: [2]int, box: ^Entity) {
	en.position = target_pos
	if box != nil {
		box.position = target_pos
		rl.PlaySound(sfx_pushbox)
	}
}

find_player :: proc() -> ^Entity {
	for &en in world.entities {
		if en.type == .Player {
			return &en
		}
	}
	return nil
}

// All entities on active layers at `pos`, excluding `self` (pass nil to keep all).
find_entities_at :: proc(pos: [2]int, self: ^Entity) -> [dynamic]^Entity {
	result := make([dynamic]^Entity, 0, context.temp_allocator)
	for &en in world.entities {
		if self != nil && &en == self {
			continue
		}
		if en.position != pos {
			continue
		}
		if !layer_is_active(en.layer) {
			continue
		}
		append(&result, &en)
	}
	return result
}

// Non-overlapping (solid) entities on active layers at `pos`, excluding `self`.
find_blocking_entities_at :: proc(pos: [2]int, self: ^Entity) -> [dynamic]^Entity {
	result := make([dynamic]^Entity, 0, context.temp_allocator)
	for &en in world.entities {
		if self != nil && &en == self {
			continue
		}
		if en.position != pos {
			continue
		}
		if en.can_overlap {
			continue
		}
		if !layer_is_active(en.layer) {
			continue
		}
		append(&result, &en)
	}
	return result
}

check_completion :: proc() -> bool {
	for &en in world.entities {
		if en.type != .Target {
			continue
		}
		if !world.layers[en.layer].is_visible {
			return false
		}
		has_cargo := false
		for b in find_blocking_entities_at(en.position, nil) {
			if b.type == .Cargo {
				has_cargo = true
				break
			}
		}
		if !has_cargo {
			return false
		}
	}

	if !is_completed {
		rl.PlaySound(sfx_activate)
	}
	// when player enters the flag, load next level
	player := find_player()
	for e in find_entities_at(player.position, player) {
		if e.type == .Flag {
			log.info("Load next level!")
			rl.PlaySound(sfx_complete)
			level_load_by_index(current_level_index + 1)
			break
		}
	}
	return true
}
