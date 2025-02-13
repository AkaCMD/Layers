package game

import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
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
targets: [dynamic]Entity

font: rl.Font

is_completed: bool
should_show_tip: bool = true
current_level_index: int

// UI
eyeball_1_bounds: rl.Rectangle
eyeball_2_bounds: rl.Rectangle

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

TextureID :: enum {
	TEXTURE_none,
	TEXTURE_player,
	TEXTURE_cargo,
	TEXTURE_wall,
	TEXTURE_target,
	TEXTURE_flag_ok,
	TEXTURE_flag_no,
	TEXTURE_visible,
	TEXTURE_invisible,
	TEXTURE_move,
	TEXTURE_reset,
	TEXTURE_undo,
	TEXTURE_humanmade,
	TEXTURE_chain,
}

textures: [TextureID]rl.Texture2D

get_texture :: proc(id: TextureID) -> rl.Texture2D {
	if id >= .TEXTURE_none {
		return textures[id]
	}
	return textures[.TEXTURE_none]
}

get_texture_id_from_type :: proc(type: Entity_Type) -> TextureID {
	switch type {
	case .Player:
		return .TEXTURE_player
	case .Cargo:
		return .TEXTURE_cargo
	case .Wall:
		return .TEXTURE_wall
	case .Target:
		return .TEXTURE_target
	case .Flag:
		if is_completed {
			return .TEXTURE_flag_ok
		} else {
			return .TEXTURE_flag_no
		}
	case:
		return .TEXTURE_none
	}
}

icon: rl.Image

Layer :: struct {
	entities:   [dynamic]Entity,
	is_visible: bool,
	order:      int,
}

get_layer_by_num :: proc(num: int) -> Layer {
	if num == 1 {
		return level.layer_1
	} else {
		return level.layer_2
	}
}

clone_layer :: proc(layer: ^Layer) -> ^Layer {
	new_layer := new(Layer, arena_allocator)
	new_layer.is_visible = layer.is_visible
	new_layer.order = layer.order

	// Clone the dynamic array of entities
	new_layer.entities = make([dynamic]Entity, len(layer.entities), arena_allocator)
	copy(new_layer.entities[:], layer.entities[:])

	return new_layer
}

clone_level :: proc(level: ^Level) -> Level {
	new_level: Level
	new_level.layer_1 = clone_layer(&level.layer_1)^
	new_level.layer_2 = clone_layer(&level.layer_2)^
	return new_level
}

Level :: struct {
	layer_1: Layer,
	layer_2: Layer,
}

level := Level {
	layer_1 = Layer{is_visible = true, order = 1},
	layer_2 = Layer{is_visible = true, order = 2},
}

Record :: struct {
	level:           Level,
	player_position: [2]int,
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

Entity :: struct {
	type:        Entity_Type,
	texture_id:  TextureID,
	position:    [2]int,
	layer:       int, // 1 or 2
	priority:    int, // from 0
	can_overlap: bool,
}

Player :: struct {
	using entity: Entity,
	is_flipped:   bool,
}

player := Player{}
setup_player :: proc(en: ^Entity) {
	en.texture_id = .TEXTURE_player
	en.type = .Player
	en.position = {1, 1}
	en.priority = 3
}

setup_cargo :: proc(en: ^Entity) {
	en.texture_id = .TEXTURE_cargo
	en.type = .Cargo
	en.priority = 3
}

setup_wall :: proc(en: ^Entity) {
	en.texture_id = .TEXTURE_wall
	en.type = .Wall
	en.priority = 3
}

setup_flag :: proc(en: ^Entity) {
	en.texture_id = .TEXTURE_flag_no
	en.type = .Flag
	en.priority = 2
	en.can_overlap = true
}

setup_target :: proc(en: ^Entity) {
	en.texture_id = .TEXTURE_target
	en.type = .Target
	en.priority = 2
	en.can_overlap = true
	append(&targets, en^)
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

	// draw level
	if level.layer_2.is_visible {
		for &entity in level.layer_2.entities {
			if entity.type == .Flag {
				if is_completed {
					entity.texture_id = .TEXTURE_flag_ok
				} else {
					entity.texture_id = .TEXTURE_flag_no
				}
			}
			rl.DrawTextureV(
				textures[entity.texture_id],
				rl.Vector2{f32(entity.position.x * GRID_SIZE), f32(entity.position.y * GRID_SIZE)},
				rl.Color{255, 255, 255, HALF_ALPHA_VALUE},
			)
		}
	}

	if level.layer_1.is_visible {
		for &entity in level.layer_1.entities {
			if entity.type == .Flag {
				if is_completed {
					entity.texture_id = .TEXTURE_flag_ok
				} else {
					entity.texture_id = .TEXTURE_flag_no
				}
			}
			rl.DrawTextureV(
				textures[entity.texture_id],
				rl.Vector2{f32(entity.position.x * GRID_SIZE), f32(entity.position.y * GRID_SIZE)},
				rl.Color{255, 255, 255, HALF_ALPHA_VALUE},
			)
		}
	}

	// draw player
	if !player.is_flipped {
		rl.DrawTexturePro(
			textures[player.texture_id],
			rl.Rectangle {
				0,
				0,
				f32(textures[player.texture_id].width),
				f32(textures[player.texture_id].height),
			},
			rl.Rectangle {
				f32(player.position.x * GRID_SIZE),
				f32(player.position.y * GRID_SIZE),
				f32(textures[player.texture_id].width),
				f32(textures[player.texture_id].height),
			},
			rl.Vector2(0),
			0,
			rl.WHITE,
		)
	} else {
		rl.DrawTexturePro(
			textures[player.texture_id],
			rl.Rectangle {
				0,
				0,
				-f32(textures[player.texture_id].width),
				f32(textures[player.texture_id].height),
			},
			rl.Rectangle {
				f32(player.position.x * GRID_SIZE),
				f32(player.position.y * GRID_SIZE),
				f32(textures[player.texture_id].width),
				f32(textures[player.texture_id].height),
			},
			rl.Vector2(0),
			0,
			rl.WHITE,
		)
	}

	// draw text and ui
	// :ui texture positions
	rl.DrawTextEx(font, "Layer 1", rl.Vector2{690, 10}, 22, 1.2, MY_BLACK)
	rl.DrawTextEx(font, "Layer 2", rl.Vector2{690, 42}, 22, 1.2, MY_BLACK)
	rl.DrawTextureV(
		textures[.TEXTURE_chain],
		rl.Vector2{eyeball_2_bounds.x, eyeball_2_bounds.y - 28},
		rl.Color{255, 255, 255, 150},
	)
	if level.layer_1.is_visible {
		rl.DrawTextureV(
			textures[.TEXTURE_visible],
			rl.Vector2{eyeball_1_bounds.x, eyeball_1_bounds.y - 13},
			rl.WHITE,
		)
	} else {
		rl.DrawTextureV(
			textures[.TEXTURE_invisible],
			rl.Vector2{eyeball_1_bounds.x, eyeball_1_bounds.y - 13},
			rl.WHITE,
		)
	}
	if level.layer_2.is_visible {
		rl.DrawTextureV(
			textures[.TEXTURE_visible],
			rl.Vector2{eyeball_2_bounds.x, eyeball_2_bounds.y - 13},
			rl.WHITE,
		)
	} else {
		rl.DrawTextureV(
			textures[.TEXTURE_invisible],
			rl.Vector2{eyeball_2_bounds.x, eyeball_2_bounds.y - 13},
			rl.WHITE,
		)
	}

	height :: 420
	rl.DrawTexture(textures[.TEXTURE_move], 645, height, rl.WHITE)
	rl.DrawTexture(textures[.TEXTURE_undo], 645, height + 110, rl.WHITE)
	rl.DrawTexture(textures[.TEXTURE_reset], 645 + 64, height + 110, rl.WHITE)
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
		record.level = clone_level(&level)
		record.player_position = player.position
		append(&undo_stack, record^)
		rl.PlaySound(sfx_footstep)
	}
}

// :init
game_init :: proc() {
	// load assets
	icon = rl.LoadImage("assets/icon.png")
	rl.SetWindowIcon(icon)
	font = rl.LoadFont("assets/fonts/PixelifySans-Regular.ttf")
	textures[.TEXTURE_player] = rl.LoadTexture("assets/textures/duck.png")
	textures[.TEXTURE_cargo] = rl.LoadTexture("assets/textures/cargo.png")
	textures[.TEXTURE_wall] = rl.LoadTexture("assets/textures/wall.png")
	textures[.TEXTURE_flag_ok] = rl.LoadTexture("assets/textures/flag_ok.png")
	textures[.TEXTURE_flag_no] = rl.LoadTexture("assets/textures/flag_no.png")
	textures[.TEXTURE_target] = rl.LoadTexture("assets/textures/target.png")
	textures[.TEXTURE_visible] = rl.LoadTexture("assets/textures/visible.png")
	textures[.TEXTURE_invisible] = rl.LoadTexture("assets/textures/invisible.png")
	textures[.TEXTURE_move] = rl.LoadTexture("assets/textures/move.png")
	textures[.TEXTURE_reset] = rl.LoadTexture("assets/textures/reset.png")
	textures[.TEXTURE_undo] = rl.LoadTexture("assets/textures/undo.png")
	textures[.TEXTURE_humanmade] = rl.LoadTexture("assets/textures/88x31-light.png")
	textures[.TEXTURE_chain] = rl.LoadTexture("assets/textures/chain.png")

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
	eyeball_1_bounds = rl.Rectangle {
		630,
		1,
		f32(textures[.TEXTURE_visible].width),
		f32(textures[.TEXTURE_visible].height / 2),
	}

	eyeball_2_bounds = rl.Rectangle {
		630,
		33,
		f32(textures[.TEXTURE_visible].width),
		f32(textures[.TEXTURE_visible].height / 2),
	}
}

// :update
game_update :: proc() {
	get_move_input()
	#partial switch input {
	case .Up:
		move(&player, {0, -1})
	case .Down:
		move(&player, {0, 1})
	case .Left:
		move(&player, {-1, 0})
		player.is_flipped = true
	case .Right:
		move(&player, {1, 0})
		player.is_flipped = false
	}

	// toggle layer's visibility
	if rl.CheckCollisionPointRec(mouse_position, eyeball_1_bounds) {
		rl.DrawRectangleLinesEx(
			rl.Rectangle{eyeball_1_bounds.x + 10, eyeball_1_bounds.y + 5, 130, 30},
			2,
			MY_PURPLE,
		)
		if rl.IsMouseButtonPressed(.LEFT) {
			should_show_tip = false
			level.layer_1.is_visible = !level.layer_1.is_visible
			if !level.layer_1.is_visible && !level.layer_2.is_visible {
				level.layer_2.is_visible = true
			}
			rl.PlaySound(sfx_switch)
		}
	}
	if rl.CheckCollisionPointRec(mouse_position, eyeball_2_bounds) {
		rl.DrawRectangleLinesEx(
			rl.Rectangle{eyeball_2_bounds.x + 10, eyeball_2_bounds.y + 5, 130, 30},
			2,
			MY_PURPLE,
		)
		if rl.IsMouseButtonPressed(.LEFT) {
			should_show_tip = false
			level.layer_2.is_visible = !level.layer_2.is_visible
			if !level.layer_1.is_visible && !level.layer_2.is_visible {
				level.layer_1.is_visible = true
			}
			rl.PlaySound(sfx_switch)
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
	// Check for overlapping entities
	en_1, en_2 := find_non_overlap_entities_in_positon(en.position)
	box: ^Entity = nil

	if en.type == .Player {
		box = select_cargo(en_1, en_2)
	}

	// Determine target position
	target_pos := en.position + dir
	if !is_within_bounds(target_pos) {
		return false // Out of bounds, do nothing
	}

	entity_in_l1, entity_in_l2 := find_non_overlap_entities_in_positon(target_pos)

	if can_move_to(entity_in_l1, entity_in_l2) {
		update_position(en, target_pos, box)
		return true
	}

	if try_move_cargo(entity_in_l1, dir, en, target_pos, box) &&
	   try_move_cargo(entity_in_l2, dir, en, target_pos, box) {
		return true
	}

	return false
}

select_cargo :: proc(en_1: ^Entity, en_2: ^Entity) -> ^Entity {
	if en_1 != nil && en_1.type == .Cargo {
		return en_1
	} else if en_2 != nil && en_2.type == .Cargo {
		return en_2
	}
	return nil
}

is_within_bounds :: proc(pos: [2]int) -> bool {
	return pos.x >= 0 && pos.x < GRID_COUNT && pos.y >= 0 && pos.y < GRID_COUNT
}

can_move_to :: proc(entity_in_l1: ^Entity, entity_in_l2: ^Entity) -> bool {
	return(
		(entity_in_l1 == nil || entity_in_l1.can_overlap) &&
		(entity_in_l2 == nil || entity_in_l2.can_overlap) \
	)
}

try_move_cargo :: proc(
	entity: ^Entity,
	dir: [2]int,
	en: ^Entity,
	target_pos: [2]int,
	box: ^Entity,
) -> bool {
	if entity != nil && entity.type == .Cargo {
		if !is_within_bounds(entity.position + dir) {
			return false // Out of bounds, do nothing
		}
		if en_1, en_2 := find_non_overlap_entities_in_positon(entity.position + dir);
		   (en_1 == nil) && (en_2 == nil) {
			update_position(en, target_pos, box)
			entity.position += dir
			rl.PlaySound(sfx_pushbox)
			return true
		} else {
			return false
		}
	}
	return true
}

update_position :: proc(en: ^Entity, target_pos: [2]int, box: ^Entity) {
	en.position = target_pos
	if box != nil {
		box.position = target_pos
		rl.PlaySound(sfx_pushbox)
	}
}

find_entities_in_position :: proc(pos: [2]int) -> (^Entity, ^Entity) {
	entity_in_l1: ^Entity = nil
	entity_in_l2: ^Entity = nil

	if level.layer_1.is_visible == true {
		for &en in level.layer_1.entities {
			if en.position == pos {
				entity_in_l1 = &en
				break
			}
		}
	}

	if level.layer_2.is_visible == true {
		for &en in level.layer_2.entities {
			if en.position == pos {
				entity_in_l2 = &en
				break
			}
		}
	}

	return entity_in_l1, entity_in_l2
}

find_non_overlap_entities_in_positon :: proc(pos: [2]int) -> (^Entity, ^Entity) {
	entity_in_l1: ^Entity = nil
	entity_in_l2: ^Entity = nil

	if level.layer_1.is_visible == true {
		for &en in level.layer_1.entities {
			if en.position == pos && !en.can_overlap {
				entity_in_l1 = &en
				break
			}
		}
	}

	if level.layer_2.is_visible == true {
		for &en in level.layer_2.entities {
			if en.position == pos && !en.can_overlap {
				entity_in_l2 = &en
				break
			}
		}
	}

	return entity_in_l1, entity_in_l2
}

check_completion :: proc() -> bool {
	for target in targets {
		if get_layer_by_num(target.layer).is_visible == false {
			return false
		}
		en_1, en_2 := find_non_overlap_entities_in_positon(target.position)
		if (en_1 == nil || (en_1 != nil && en_1.type != .Cargo)) &&
		   (en_2 == nil || (en_2 != nil && en_2.type != .Cargo)) {
			return false
		}
	}

	if !is_completed {
		rl.PlaySound(sfx_activate)
	}
	// when player enter the flag, load next level
	en_1, en_2 := find_entities_in_position(player.position)
	if (en_1 != nil && en_1.type == .Flag) || (en_2 != nil && en_2.type == .Flag) {
		log.info("Load next level!")
		rl.PlaySound(sfx_complete)
		level_load_by_index(current_level_index + 1)
	}
	return true
}


level_load_from_txt :: proc(index: int) -> bool {
	setup_player(&player)

	builder := strings.builder_make(context.temp_allocator)

	path1 := fmt.sbprintf(&builder, "assets/levels/%d-l1.txt", index)
	if l1_data, ok := read_entire_file(path1, context.temp_allocator); ok {
		level_load_layer_from_txt(1, string(l1_data))
		log.infof("Loaded level%d layer1!", index)
	} else {
		log.infof("Could't load level%d layer1!", index)
		return false
	}

	strings.builder_reset(&builder)

	path2 := fmt.sbprintf(&builder, "assets/levels/%d-l2.txt", index)
	if l2_data, ok := read_entire_file(path2, context.temp_allocator); ok {
		level_load_layer_from_txt(2, string(l2_data))
		log.infof("Loaded level%d layer2!", index)
	} else {
		log.infof("Could't load level%d layer2!", index)
		return false
	}
	return true
}

level_load_layer_from_txt :: proc(layer_index: int, content: string) {
	x := 0
	y := 0

	fmt.printf("\nlayer %d:\n", layer_index)
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
		if layer_index == 1 {
			append(&level.layer_1.entities, en^)
		} else if layer_index == 2 {
			append(&level.layer_2.entities, en^)
		} else {
			log.error("Invalid layer index!")
		}
	}
}

level_unload :: proc() {
	resize(&level.layer_1.entities, 0)
	resize(&level.layer_2.entities, 0)
	resize(&targets, 0)
	resize(&undo_stack, 0)

	is_completed = false
}

unload_game :: proc() {
	delete(level.layer_1.entities)
	delete(level.layer_2.entities)
	delete(undo_stack)
	delete(targets)
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
	level = record.level
	player.position = record.player_position
	log.info("undo")
	delete(record.level.layer_1.entities)
	delete(record.level.layer_2.entities)
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
