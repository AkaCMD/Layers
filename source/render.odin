package game

import "core:fmt"
import "core:slice"
import rl "vendor:raylib"
import hm "core:container/handle_map"

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
	it := hm.iterator_make(&world.entities)
	for en, _ in hm.iterate(&it) {
		if !layer_is_active(en.layer) {
			continue
		}
		append(&visible_entities, en)
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

// :overview
// Special view that shows every layer on its own, the stacked result, and the
// player's live position. Toggled with Tab.
visible_entities_sorted :: proc() -> [dynamic]^Entity {
	result := make([dynamic]^Entity, 0, context.temp_allocator)
	it := hm.iterator_make(&world.entities)
	for en, _ in hm.iterate(&it) {
		if !layer_is_active(en.layer) {
			continue
		}
		append(&result, en)
	}
	slice.stable_sort_by(result[:], proc(a, b: ^Entity) -> bool {
		return entity_draw_order(a) < entity_draw_order(b)
	})
	return result
}

entities_on_layer :: proc(layer: int) -> [dynamic]^Entity {
	result := make([dynamic]^Entity, 0, context.temp_allocator)
	it := hm.iterator_make(&world.entities)
	for en, _ in hm.iterate(&it) {
		if en.layer == layer {
			append(&result, en)
		}
	}
	return result
}

draw_scaled_entity :: proc(en: ^Entity, origin: rl.Vector2, cell: f32) {
	if en.type == .Flag {
		if is_completed {
			en.texture = .Flag_Ok
		} else {
			en.texture = .Flag_No
		}
	}

	rect := atlas_textures[en.texture].rect
	source := rect
	if en.type == .Player && en.is_flipped {
		source.width = -source.width
	}
	rl.DrawTexturePro(
		atlas,
		source,
		rl.Rectangle {
			origin.x + f32(en.position.x) * cell,
			origin.y + f32(en.position.y) * cell,
			cell,
			cell,
		},
		rl.Vector2(0),
		0,
		rl.WHITE,
	)
}

draw_panel :: proc(origin: rl.Vector2, cell: f32, entities: [dynamic]^Entity, dim: bool) {
	size := cell * f32(GRID_COUNT)

	rl.DrawRectangleRec(rl.Rectangle{origin.x, origin.y, size, size}, rl.RAYWHITE)

	for i := 0; i <= GRID_COUNT; i += 1 {
		line_color := rl.Color{MY_GREY.r, MY_GREY.g, MY_GREY.b, 80}
		rl.DrawLineEx(
			rl.Vector2{origin.x + f32(i) * cell, origin.y},
			rl.Vector2{origin.x + f32(i) * cell, origin.y + size},
			1,
			line_color,
		)
		rl.DrawLineEx(
			rl.Vector2{origin.x, origin.y + f32(i) * cell},
			rl.Vector2{origin.x + size, origin.y + f32(i) * cell},
			1,
			line_color,
		)
	}

	for en in entities {
		if en.type == .Player {
			continue
		}
		draw_scaled_entity(en, origin, cell)
	}

	player := find_player()
	if player != nil {
		draw_scaled_entity(player, origin, cell)
		rl.DrawRectangleLinesEx(
			rl.Rectangle {
				origin.x + f32(player.position.x) * cell,
				origin.y + f32(player.position.y) * cell,
				cell,
				cell,
			},
			2,
			MY_ORANGE,
		)
	}

	if dim {
		rl.DrawRectangleRec(rl.Rectangle{origin.x, origin.y, size, size}, rl.Color{110, 110, 110, 170})
	}

	rl.DrawRectangleLinesEx(rl.Rectangle{origin.x, origin.y, size, size}, 2, MY_BLACK)
}

OVERVIEW_EYE_SIZE :: f32(48)
OVERVIEW_LIST_ROW_H :: f32(60)
// Match the normal game's font sizes (which are drawn at 1.5x zoom):
// "Layer %d" is font 22, "by cmd" is font 32 in world space.
OVERVIEW_FONT_SIZE :: f32(22 * ZOOM)
OVERVIEW_SYMBOL_FONT_SIZE :: f32(32 * ZOOM)
OVERVIEW_PANEL_GAP :: f32(80)

compute_overview_layout :: proc() {
	clear(&overview_eye_bounds)
	clear(&overview_panel_x)

	n := len(world.layers)
	total := n + 1

	view_w := f32(OVERVIEW_SCREEN_WIDTH)
	view_h := f32(OVERVIEW_SCREEN_HEIGHT)

	margin: f32 = 16

	// vertical layer list (buttons + names), top to bottom, on the right
	for i in 0 ..< n {
		y := margin + f32(i) * OVERVIEW_LIST_ROW_H
		x := view_w - margin - OVERVIEW_EYE_SIZE
		append(&overview_eye_bounds, rl.Rectangle{x, y, OVERVIEW_EYE_SIZE, OVERVIEW_EYE_SIZE})
	}

	// three equal panels side by side, below the list
	panels_top := margin + f32(n) * OVERVIEW_LIST_ROW_H + margin
	avail_w := view_w - 2 * margin
	avail_h := view_h - panels_top - margin

	panel_w := (avail_w - OVERVIEW_PANEL_GAP * f32(total - 1)) / f32(total)
	cell := min(panel_w, avail_h) / f32(GRID_COUNT)
	size := cell * f32(GRID_COUNT)

	overview_cell = cell
	overview_panel_y = panels_top + (avail_h - size) * 0.5

	for j in 0 ..< total {
		append(&overview_panel_x, margin + f32(j) * (panel_w + OVERVIEW_PANEL_GAP))
	}
}

draw_overview :: proc() {
	rl.ClearBackground(MY_GREY)

	n := len(world.layers)

	// layer list: names + eye buttons, top to bottom, on the right
	for i in 0 ..< n {
		b := overview_eye_bounds[i]
		label := fmt.ctprintf("Layer %d", i + 1)
		name_w := rl.MeasureTextEx(font, label, OVERVIEW_FONT_SIZE, 1).x
		eye_texture := world.layers[i].is_visible ? atlas_textures[.Visible].rect : atlas_textures[.Invisible].rect
		rl.DrawTexturePro(
			atlas,
			eye_texture,
			rl.Rectangle{b.x, b.y, OVERVIEW_EYE_SIZE, OVERVIEW_EYE_SIZE},
			rl.Vector2(0),
			0,
			rl.WHITE,
		)
		rl.DrawTextEx(
			font,
			label,
			rl.Vector2{b.x - name_w - 8, b.y + (OVERVIEW_EYE_SIZE - OVERVIEW_FONT_SIZE) * 0.5},
			OVERVIEW_FONT_SIZE,
			1,
			MY_BLACK,
		)

		// highlight the whole row when hovered, matching the normal view
		if rl.CheckCollisionPointRec(mouse_position, b) {
			rl.DrawRectangleLinesEx(
				rl.Rectangle{
					b.x - name_w - 16,
					b.y - 8,
					name_w + OVERVIEW_EYE_SIZE + 24,
					OVERVIEW_EYE_SIZE + 16,
				},
				2,
				MY_PURPLE,
			)
		}
	}

	// chain icon linking the layer toggles, matching the normal view
	if n > 1 {
		a := overview_eye_bounds[n - 2]
		b := overview_eye_bounds[n - 1]
		mid_y := (a.y + OVERVIEW_EYE_SIZE + b.y) * 0.5
		rl.DrawTexturePro(
			atlas,
			atlas_textures[.Chain].rect,
			rl.Rectangle{b.x, mid_y - OVERVIEW_EYE_SIZE * 0.5, OVERVIEW_EYE_SIZE, OVERVIEW_EYE_SIZE},
			rl.Vector2(0),
			0,
			rl.Color{255, 255, 255, 150},
		)
	}

	// layer panels
	for i in 0 ..< n {
		origin := rl.Vector2{overview_panel_x[i], overview_panel_y}
		draw_panel(origin, overview_cell, entities_on_layer(i), !world.layers[i].is_visible)
		rl.DrawTextEx(font, fmt.ctprintf("Layer %d", i + 1), rl.Vector2{origin.x, origin.y - OVERVIEW_FONT_SIZE - 6}, OVERVIEW_FONT_SIZE, 1, MY_BLACK)
	}

	// stacked result panel
	{
		origin := rl.Vector2{overview_panel_x[n], overview_panel_y}
		draw_panel(origin, overview_cell, visible_entities_sorted(), false)
		rl.DrawTextEx(font, "Stacked Result", rl.Vector2{origin.x, origin.y - OVERVIEW_FONT_SIZE - 6}, OVERVIEW_FONT_SIZE, 1, MY_BLACK)
	}

	// "+" and "=" symbols between panels
	size := overview_cell * f32(GRID_COUNT)
	center_y := overview_panel_y + size * 0.5
	for i in 0 ..< n - 1 {
		x := (overview_panel_x[i] + size + overview_panel_x[i + 1]) * 0.5
		draw_overview_symbol("+", rl.Vector2{x, center_y})
	}
	{
		x := (overview_panel_x[n - 1] + size + overview_panel_x[n]) * 0.5
		draw_overview_symbol("=", rl.Vector2{x, center_y})
	}
}

draw_overview_symbol :: proc(text: cstring, center: rl.Vector2) {
	m := rl.MeasureTextEx(font, text, OVERVIEW_SYMBOL_FONT_SIZE, 1)
	rl.DrawTextEx(font, text, rl.Vector2{center.x - m.x * 0.5, center.y - m.y * 0.5}, OVERVIEW_SYMBOL_FONT_SIZE, 1, MY_BLACK)
}
