package game

import "core:fmt"
import "core:slice"
import rl "vendor:raylib"

entity_draw_order :: proc(en: ^Entity) -> int {
	if en.layer < 0 {
		return 1 << 30
	}
	return world.layers[en.layer].order
}

draw_entity :: proc(en: ^Entity) {
	if en.type == .Flag {
		if is_completed {
			en.texture = .Flag_Ok
		} else {
			en.texture = .Flag_No
		}
	}

	if en.type == .Player {
		rect := atlas_textures[en.texture].rect
		source := rect
		if en.is_flipped {
			source.width = -source.width
		}
		rl.DrawTexturePro(
			atlas,
			source,
			rl.Rectangle {
				f32(en.position.x * GRID_SIZE),
				f32(en.position.y * GRID_SIZE),
				rect.width,
				rect.height,
			},
			rl.Vector2(0),
			0,
			rl.WHITE,
		)
	} else {
		rl.DrawTextureRec(
			atlas,
			atlas_textures[en.texture].rect,
			rl.Vector2{f32(en.position.x * GRID_SIZE), f32(en.position.y * GRID_SIZE)},
			rl.Color{255, 255, 255, HALF_ALPHA_VALUE},
		)
	}
}

// :draw
draw :: proc() {
	rl.ClearBackground(rl.RAYWHITE)
	// draw grid lines
	for i := 0; i < GRID_COUNT + 1; i += 1 {
		rl.DrawLineEx(
			rl.Vector2{f32(GRID_SIZE * i) + offset.x / 2, offset.y / 2},
			rl.Vector2{f32(GRID_SIZE * i) + offset.x / 2, GRID_COUNT * GRID_SIZE - offset.y / 2},
			2,
			rl.Color{MY_GREY.r, MY_GREY.g, MY_GREY.b, 80},
		)
	}

	for i := 0; i < GRID_COUNT + 1; i += 1 {
		rl.DrawLineEx(
			rl.Vector2{offset.x / 2, f32(GRID_SIZE * i)},
			rl.Vector2{GRID_COUNT * GRID_SIZE + offset.x / 2, f32(GRID_SIZE * i)},
			2,
			rl.Color{MY_GREY.r, MY_GREY.g, MY_GREY.b, 80},
		)
	}

	// draw all entities in one pass, ordered by layer
	visible_entities := make([dynamic]^Entity, 0, context.temp_allocator)
	for &en in world.entities {
		if !layer_is_active(en.layer) {
			continue
		}
		append(&visible_entities, &en)
	}
	slice.stable_sort_by(visible_entities[:], proc(a, b: ^Entity) -> bool {
		return entity_draw_order(a) < entity_draw_order(b)
	})
	for en in visible_entities {
		draw_entity(en)
	}

	// draw text and ui
	// :ui texture positions
	for i in 0 ..< len(world.layers) {
		rl.DrawTextEx(font, fmt.ctprintf("Layer %d", i + 1), rl.Vector2{690, f32(10 + i * 32)}, 22, 1.2, MY_BLACK)
		if world.layers[i].is_visible {
			rl.DrawTextureRec(
				atlas,
				atlas_textures[.Visible].rect,
				rl.Vector2{eyeball_bounds[i].x, eyeball_bounds[i].y - 13},
				rl.WHITE,
			)
		} else {
			rl.DrawTextureRec(
				atlas,
				atlas_textures[.Invisible].rect,
				rl.Vector2{eyeball_bounds[i].x, eyeball_bounds[i].y - 13},
				rl.WHITE,
			)
		}
	}
	if len(world.layers) > 0 {
		last := len(world.layers) - 1
		rl.DrawTextureRec(
			atlas,
			atlas_textures[.Chain].rect,
			rl.Vector2{eyeball_bounds[last].x, eyeball_bounds[last].y - 28},
			rl.Color{255, 255, 255, 150},
		)
	}

	height :: 420
	rl.DrawTextureRec(atlas, atlas_textures[.Move].rect, rl.Vector2{645, height}, rl.WHITE)
	rl.DrawTextureRec(atlas, atlas_textures[.Undo].rect, rl.Vector2{645, height + 110}, rl.WHITE)
	rl.DrawTextureRec(atlas, atlas_textures[.Reset].rect, rl.Vector2{645 + 64, height + 110}, rl.WHITE)
	rl.DrawTextEx(font, "by cmd", rl.Vector2{665, 606}, 32, 1.2, MY_BLACK)
	if should_show_tip {
		show_tip(
			"Hi! You can click on upper right corner's eyeball\nto toggle the visibility of layers:]",
		)
	}
}

// :tip
show_tip :: proc(text: cstring) {
	x: f32 = 5
	y: f32 = 5
	padding_x: f32 = 5
	padding_y: f32 = 3
	bounds := rl.Rectangle{x, y, 460, 54}
	rl.DrawRectangleRounded(bounds, 0.3, 10, rl.RAYWHITE)
	rl.DrawRectangleRoundedLinesEx(bounds, 0.3, 20, 2, MY_ORANGE)
	rl.DrawTextEx(font, text, rl.Vector2{x + padding_x, y + padding_y}, 22, 1, MY_BLACK)
}

congratulations :: proc() {
	rl.DrawTextEx(font, "Congratulations!", rl.Vector2{300, 300}, 30, 1, MY_YELLOW)
}
