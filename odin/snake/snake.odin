package snake

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

GRID_CELL_SIZE      :: 40
GRID_WIDTH_PX       :: 800
GRID_HEIGHT_PX      :: 800
GRID_WIDTH          :: GRID_WIDTH_PX / GRID_CELL_SIZE
GRID_HEIGHT         :: GRID_HEIGHT_PX / GRID_CELL_SIZE
GRID_MARGIN: [2]i32 : { GRID_CELL_SIZE, GRID_CELL_SIZE * 2 }

Snake :: struct {
    x: i32,
    y: i32,
    next: ^Snake,
}

Direction :: enum{
    Up,
    Down,
    Left,
    Right,
    Unknown,
}

Direction_Vectors := [Direction][2]i32 {
    .Up      = {  0, -1 },
    .Down    = {  0,  1 },
    .Left    = { -1,  0 },
    .Right   = {  1,  0 },
    .Unknown = {  0,  0 },
}

GameState :: enum{
    Play,
    Game_Over,
}

state: GameState = .Play
grid: [GRID_WIDTH][GRID_HEIGHT]bool
free_cells: [dynamic][2]i32
snake := Snake{x = GRID_WIDTH / 2, y = GRID_HEIGHT / 2}
snake_poll: [dynamic; GRID_WIDTH * GRID_HEIGHT]Snake
apple: [2]i32 = { 0, 0 }
score := 0
tick_timer: f32 = 0.0
tick_interval: f32 = 0.10

get_opposite_direction :: proc(direction: Direction) -> Direction {
    switch direction {
    case .Up: return .Down
    case .Down: return .Up
    case .Left: return .Right
    case .Right: return .Left
    case .Unknown: return .Unknown
    }

    return .Unknown
}

to_grid_x :: proc(pos: i32) -> i32 {
    return pos * GRID_CELL_SIZE + GRID_MARGIN.x
}

to_grid_y :: proc(pos: i32) -> i32 {
    return pos * GRID_CELL_SIZE + GRID_MARGIN.y
}

draw_score :: proc() {
    rl.DrawText(fmt.ctprintf("SCORE: %d", score), GRID_MARGIN.x, GRID_MARGIN.y / 4, GRID_CELL_SIZE, rl.RED)
}

draw_snake :: proc() {
    for s := &snake; s != nil; s = s.next {
        rl.DrawRectangle(to_grid_x(s.x), to_grid_y(s.y), GRID_CELL_SIZE, GRID_CELL_SIZE, rl.WHITE)
    }
}

draw_apple :: proc() {
    rl.DrawRectangle(to_grid_x(apple.x), to_grid_y(apple.y), GRID_CELL_SIZE, GRID_CELL_SIZE, rl.RED)
}

draw_bg :: proc() {
    rl.DrawRectangleLines(GRID_MARGIN.x, GRID_MARGIN.y, GRID_WIDTH_PX, GRID_HEIGHT_PX, rl.WHITE)
    rl.ClearBackground(rl.BLACK)
}

randomize_apple_position :: proc() {
    lo :: 0
    hi := len(free_cells)

    if hi == 0 {
        hi = GRID_WIDTH
        for apple.x = cast(i32)rand.int_range(lo, hi); apple.x == snake.x; apple.x = cast(i32)rand.int_range(lo, hi) {}
        for apple.y = cast(i32)rand.int_range(lo, hi); apple.y == snake.y; apple.y = cast(i32)rand.int_range(lo, hi) {}
        return
    }

    random_free_pos := free_cells[rand.int_range(lo, hi)]
    apple.x = random_free_pos.x
    apple.y = random_free_pos.y
}

move_snake :: proc(direction: Direction, direction_changed: bool) {
    prev_x := snake.x
    prev_y := snake.y

    tick_timer += rl.GetFrameTime()
    if (tick_timer >= tick_interval || direction_changed) {
        snake.x += Direction_Vectors[direction].x
        snake.y += Direction_Vectors[direction].y
        if snake.x >= GRID_WIDTH {
            snake.x = 0
        }
        if snake.x < 0 {
            snake.x = GRID_WIDTH - 1
        }
        if snake.y >= GRID_HEIGHT {
            snake.y = 0
        }
        if snake.y < 0 {
            snake.y = GRID_HEIGHT - 1
        }

        grid[prev_x][prev_y] = false
        grid[snake.x][snake.y] = true
        if snake.next != nil {
            for s := snake.next; s != nil; s = s.next {
                if snake.x == s.x && snake.y == s.y {
                    state = .Game_Over
                    return
                }

                px := s.x
                py := s.y
                s.x = prev_x
                s.y = prev_y
                prev_x = px
                prev_y = py

                grid[prev_x][prev_y] = false
                grid[s.x][s.y] = true
            }
        }

        clear(&free_cells)
        for i in 0..<(GRID_WIDTH) {
            for j in 0..<(GRID_HEIGHT) {
                if !grid[i][j] {
                    append(&free_cells, [2]i32{ cast(i32)i, cast(i32)j })
                }
            }
        }

        if snake.x == apple.x && snake.y == apple.y {
            score += 10
            randomize_apple_position()
            append(&snake_poll, Snake{x = snake.x, y = snake.y})
            new_segment := &snake_poll[len(snake_poll) - 1]
            for tail := &snake; ; tail = tail.next {
                if tail.next == nil {
                    tail.next = new_segment
                    break
                }
            }
        }

        tick_timer = 0.0
    }
}

reset :: proc() {
    score = 0
    for i in 0..<(GRID_WIDTH) {
        for j in 0..<(GRID_HEIGHT) {
            grid[i][j] = false
        }
    }
    clear(&free_cells)
    snake = Snake{x = GRID_WIDTH / 2, y = GRID_HEIGHT / 2}
    clear(&snake_poll)
    apple = { 0, 0 }
    state = .Play
}

main :: proc() {
    rl.InitWindow(GRID_WIDTH_PX + GRID_MARGIN.x * 2, GRID_HEIGHT_PX + GRID_MARGIN.y + GRID_MARGIN.x, "Odinake")
    defer rl.CloseWindow()

    randomize_apple_position()
    direction: Direction = .Unknown
    for !rl.WindowShouldClose() {
        key_pressed := rl.GetKeyPressed()
        if state == .Play {
            new_direction: Direction = .Unknown
            #partial switch key_pressed {
                case .LEFT, .A, .J: new_direction = .Left
                case .RIGHT, .D, .L: new_direction = .Right
                case .UP, .W, .I: new_direction = .Up
                case .DOWN, .S, .K: new_direction = .Down
            }

            direction_changed := false
            if (snake.next == nil || new_direction != get_opposite_direction(direction)) && new_direction != .Unknown {
                direction = new_direction
                direction_changed = true
            }
            move_snake(direction, direction_changed)
        } else {
            if key_pressed != .KEY_NULL {
                direction = .Unknown
                reset()
                continue
            }
        }

        rl.BeginDrawing()
            draw_score()

            if state == .Play {
                draw_snake()
                draw_apple()
            } else {
                rl.DrawText("GAME OVER", GRID_WIDTH_PX / 2 - 110, GRID_HEIGHT_PX / 2, 50, rl.RED)
            }

            draw_bg()
        rl.EndDrawing()
    }

    delete(free_cells)
}
