package game

import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

// color palettes
MY_YELLOW_BROWN :: rl.Color{221, 169, 99, 255}
MY_BROWN :: rl.Color{201, 129, 75, 255}
MY_BLACK :: rl.Color{37, 39, 42, 255}
MY_LIGHT_BROWN :: rl.Color{219, 193, 175, 255}
MY_ORANGE :: rl.Color{207, 106, 79, 255}
MY_YELLOW :: rl.Color{224, 185, 74, 255}
MY_GREEN :: rl.Color{178, 175, 92, 255}
MY_GREY :: rl.Color{167, 167, 158, 255}
MY_PURPLE :: rl.Color{155, 105, 112, 255}

GAME_SCREEN_WIDTH :: 960 + 200
GAME_SCREEN_HEIGHT :: 960
ZOOM :: 1.5
LEVEL_SIZE :: 960
GRID_COUNT :: 10
GRID_SIZE :: LEVEL_SIZE / (GRID_COUNT * ZOOM)
MAX_ENTITIES_COUNT :: 300
RATIO :: 0.8

HALF_ALPHA_VALUE :: u8(150)

// render
target: rl.RenderTexture2D
scale: f32

// atlas
Rect :: rl.Rectangle
atlas: rl.Texture

// audio
bgm: rl.Music
sfx_footstep: rl.Sound
sfx_pushbox: rl.Sound
sfx_switch: rl.Sound
sfx_activate: rl.Sound
sfx_undo: rl.Sound
sfx_complete: rl.Sound

offset := rl.Vector2{0, 0}
mouse_position: rl.Vector2

font: rl.Font

is_completed: bool
should_show_tip: bool = true
current_level_index: int

// UI
eyeball_bounds: [dynamic]rl.Rectangle

run: bool
camera: rl.Camera2D
logger: log.Logger

// Undo stack memory allocator
arena_allocator: mem.Allocator
arena: mem.Arena

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

icon: rl.Image

// Number of layers per level. Increase this and add a matching
// `assets/levels/{n}-l{layer}.txt` file to add more layers.
NUM_LAYERS :: 2
// Special layer value for entities that don't belong to any togglable layer
// (the player): always active, always drawn on top.
NO_LAYER :: -1

Layer :: struct {
	is_visible: bool,
	order:      int, // draw order; higher = drawn later (in front)
}

World :: struct {
	entities: [dynamic]Entity,
	layers:   [dynamic]Layer,
}

world := World{}

add_entity :: proc(w: ^World, e: Entity) {
	append(&w.entities, e)
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

undo_stack: [dynamic]Record

Input :: enum {
	None,
	Up,
	Down,
	Left,
	Right,
}

input: Input

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

init :: proc() {
	run = true
	// Change working directory
	// For macos, the default directory is not application directory
	rl.ChangeDirectory(rl.GetApplicationDirectory())
	// Init logger
	logger = log.create_console_logger()
	context.logger = logger

	// any memory leaks?
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorret frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	arena = mem.Arena{}
	mem.arena_init(&arena, make([]byte, 6_000_000))
	arena_allocator = mem.arena_allocator(&arena)

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(GAME_SCREEN_WIDTH * RATIO, GAME_SCREEN_HEIGHT * RATIO, "Layers")
	rl.InitAudioDevice()

	// Render texture initialization, used to hold the rendering result so we can easily resize it
	target = rl.LoadRenderTexture(GAME_SCREEN_WIDTH, GAME_SCREEN_HEIGHT)
	rl.SetTextureFilter(target.texture, rl.TextureFilter.POINT)

	rl.SetTargetFPS(60)
	init_layers()
	game_init()
	rl.PlayMusicStream(bgm)

	camera.zoom = ZOOM
}

update :: proc() {
	rl.ClearBackground(MY_GREY)
	rl.UpdateMusicStream(bgm)
	scale = RATIO
	scale = min(
		f32(rl.GetScreenWidth()) / f32(GAME_SCREEN_WIDTH),
		f32(rl.GetScreenHeight()) / f32(GAME_SCREEN_HEIGHT),
	)

	init_ui_bounds()

	rl.BeginTextureMode(target)
	{
		rl.BeginMode2D(camera)
		{
			game_update()
			draw()
		}
		rl.EndMode2D()
	}
	rl.EndTextureMode()

	// Draw scaled content to screen
	rl.BeginDrawing()
	{
		// Calculate destination rectangle for scaled drawing
		dest := rl.Rectangle {
			(f32(rl.GetScreenWidth()) - f32(GAME_SCREEN_WIDTH) * scale) * 0.5,
			(f32(rl.GetScreenHeight()) - f32(GAME_SCREEN_HEIGHT) * scale) * 0.5,
			f32(GAME_SCREEN_WIDTH) * scale,
			f32(GAME_SCREEN_HEIGHT) * scale,
		}

		// Draw render texture to screen, properly scaled
		source := rl.Rectangle{0, 0, f32(target.texture.width), f32(-target.texture.height)}
		origin := rl.Vector2{0, 0}

		rl.DrawTexturePro(target.texture, source, dest, origin, 0.0, rl.WHITE)
	}
	rl.EndDrawing()
	free_all(context.temp_allocator)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(c.int(w), c.int(h))
}

shutdown :: proc() {
	log.destroy_console_logger(logger)
	rl.CloseAudioDevice()
	rl.UnloadAudioStream(bgm)
	rl.CloseWindow()
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			run = false
		}
	}

	return run
}

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

get_move_input :: proc() {
	input = .None
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		input = .Up
	} else if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		input = .Down
	} else if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.A) {
		input = .Left
	} else if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) {
		input = .Right
	}
	mouse_position = get_mouse_position()
	if input != .None {
		// push record to undo stack
		record := new(Record, context.temp_allocator)
		record.world = clone_world(&world)
		append(&undo_stack, record^)
		rl.PlaySound(sfx_footstep)
	}
}

// :init
game_init :: proc() {
	// load assets
	atlas = rl.LoadTexture("assets/atlas.png")
	rl.SetTextureFilter(atlas, rl.TextureFilter.POINT)
	icon = rl.LoadImage("assets/icon.png")
	rl.SetWindowIcon(icon)
	font = rl.LoadFont("assets/fonts/PixelifySans-Regular.ttf")

	bgm = rl.LoadMusicStream("assets/audio/bgm.wav")
	sfx_footstep = rl.LoadSound("assets/audio/footstep.ogg")
	sfx_pushbox = rl.LoadSound("assets/audio/pushbox.ogg")
	sfx_switch = rl.LoadSound("assets/audio/switch.ogg")
	sfx_activate = rl.LoadSound("assets/audio/activate.ogg")
	sfx_undo = rl.LoadSound("assets/audio/undo.ogg")
	sfx_complete = rl.LoadSound("assets/audio/complete.ogg")
	rl.SetSoundVolume(sfx_undo, 0.5)

	if ok := level_load_from_txt(1); ok {
		current_level_index = 1
	}
}

// :ui bounds positions
init_ui_bounds :: proc() {
	visible := atlas_textures[.Visible].rect

	clear(&eyeball_bounds)
	for i in 0 ..< len(world.layers) {
		append(
			&eyeball_bounds,
			rl.Rectangle{630, f32(1 + i * 32), visible.width, visible.height / 2},
		)
	}
}

// :update
game_update :: proc() {
	get_move_input()
	player := find_player()
	#partial switch input {
	case .Up:
		move(player, {0, -1})
	case .Down:
		move(player, {0, 1})
	case .Left:
		move(player, {-1, 0})
		player.is_flipped = true
	case .Right:
		move(player, {1, 0})
		player.is_flipped = false
	}

	// toggle layer's visibility
	for i in 0 ..< len(world.layers) {
		if rl.CheckCollisionPointRec(mouse_position, eyeball_bounds[i]) {
			rl.DrawRectangleLinesEx(
				rl.Rectangle{eyeball_bounds[i].x + 10, eyeball_bounds[i].y + 5, 130, 30},
				2,
				MY_PURPLE,
			)
			if rl.IsMouseButtonPressed(.LEFT) {
				should_show_tip = false
				toggle_layer_visibility(i)
				rl.PlaySound(sfx_switch)
			}
		}
	}

	is_completed = check_completion()

	// R to reset
	if rl.IsKeyPressed(.R) {
		level_reload()
		rl.PlaySound(sfx_undo)
	}

	// Z to undo
	if rl.IsKeyPressed(.Z) {
		undo()
	}

	//  [] to switch level for test
	if rl.IsKeyPressed(.LEFT_BRACKET) {
		level_load_by_index(current_level_index - 1)
	}
	if rl.IsKeyPressed(.RIGHT_BRACKET) {
		level_load_by_index(current_level_index + 1)
	}
}

get_mouse_position :: proc() -> [2]f32 {
	mouse_position = rl.GetMousePosition()
	rl.SetMouseOffset(
		-i32((f32(rl.GetScreenWidth()) - GAME_SCREEN_WIDTH * scale) * 0.5),
		-i32((f32(rl.GetScreenHeight()) - GAME_SCREEN_HEIGHT * scale) * 0.5),
	)
	rl.SetMouseScale(1 / scale, 1 / scale)
	return mouse_position / ZOOM
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

undo :: proc() {
	if len(undo_stack) == 0 {
		return
	}
	rl.PlaySound(sfx_undo)
	record := pop(&undo_stack)
	world = record.world
	log.info("undo")
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
