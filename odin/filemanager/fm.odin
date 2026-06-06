package fm

import t "vendor/termcl"
import tb "vendor/termcl/term"

import "core:path/filepath"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

FILE_TREE_POS: uint : 2

file_list : File_List;
cwd: string
page: uint = 0
to_copy : [dynamic]os.File_Info

Mode :: enum {
    File_List,
    Search
}
mode := Mode.File_List
search_phrase : string

go_to_parent :: proc() {
    cwd = os.dir(cwd)
    page = 0
    file_list_cd(&file_list, cwd)
}

open :: proc(file_info: ^os.File_Info) {
    if file_info.type == .Directory {
        cwd = file_info.fullpath
        file_list_cd(&file_list, cwd)
        return
    }

    desc := os.Process_Desc {
		command = []string{"open", file_info.fullpath},
	}

	p, err := os.process_start(desc)
}

edit :: proc(s:  ^t.Screen, file_info: ^os.File_Info) {
    bring_back_fm :: proc(s: ^t.Screen) {
        t.set_term_mode(s, .Cbreak)
        t.enable_alt_buffer(true)
        t.hide_cursor(true)
        t.clear(s, .Everything)
        t.blit(s)
    }

    t.reset_styles(s)
    t.clear(s, .Everything)
    t.blit(s)
    t.set_term_mode(s, .Restored)
    defer bring_back_fm(s)

    desc := os.Process_Desc {
		command = []string{"nvim", file_info.fullpath},
        stdin  = os.stdin,
        stdout = os.stdout,
        stderr = os.stderr,
	}

	p, err := os.process_start(desc)
    if err == os.ERROR_NONE {
        _, _ = os.process_wait(p)
	}

    file_list_refresh(&file_list)
}

main :: proc() {
    if len(os.args) > 1 {
        path_arg := strings.clone(os.args[1])
        if strings.starts_with(path_arg, "~") {
            home_path, found := os.lookup_env("HOME", context.allocator)
            if !found || home_path == "" {
                fmt.printfln("$HOME env variable not set")
                os.exit(1)
            }
            defer delete(home_path)
            path_arg, _ = strings.replace(path_arg, "~", home_path, 1)
        }

        if !os.exists(path_arg) {
            fmt.printfln("Path %s does not exist!", path_arg)
            os.exit(1)
        }

        cwd = path_arg
    } else {
        start_cwd, cwd_err := os.get_working_directory(context.allocator)
        if cwd_err != os.ERROR_NONE {
            fmt.println("Failed to get current working directory: %s", os.error_string(cwd_err))
            os.exit(1)
        }
        cwd = start_cwd
    }

    s := t.init_screen(tb.VTABLE)
    defer t.destroy_screen(&s)
    t.set_term_mode(&s, .Cbreak)
    t.enable_alt_buffer(true)
    t.hide_cursor(true)

    term_size := t.get_term_size()
    file_list_init(&file_list, cwd, FILE_TREE_POS, 0)

    should_quit := false
    time_from_last_keypress := time.Tick{0}
    last_keypress: t.Key
    last_mod: t.Mod
    for !should_quit {
        term_size = t.get_term_size()
        t.clear(&s, .Everything)

        draw_textf(&s, 0, 0, "%s", cwd)
        t.blit(&s)

        file_list_draw(&file_list)

        if mode == .Search {
            input := tb.read_raw_blocking(&s) or_continue
            parsed := tb.parse_keyboard_input(input) or_continue
            if parsed.key == .Escape {
                mode = .File_List
                delete(search_phrase)
                search_phrase = ""
                file_list_clear_search(&file_list)
                continue
            } else if parsed.key == .Enter {
                mode = .File_List
                file_list_select_next_search_result(&file_list)
                continue
            }

            search_phrase = strings.concatenate({search_phrase, input}) or_continue
            file_list_search(&file_list, search_phrase)
            continue
        }

        input := t.read_blocking(&s).(t.Keyboard_Input) or_continue
        #partial switch input.key {
        case .Q: should_quit = true
        case .J: file_list_next(&file_list)
        case .K: file_list_prev(&file_list)
        case .H: go_to_parent()
        case .L, .Enter: {
            open(&file_list.entries[file_list.current])
        }
        case .Y: {
            for entry in file_list.marked_files {
                append(&to_copy, entry^)
            }
            file_list_unmark_all(&file_list)
            file_list_refresh(&file_list)
        }
        case .P: {
            for entry in to_copy {
                destination := filepath.join({cwd, entry.name}) or_continue
                defer delete(destination)
                conflict_suffix := 0
                for os.exists(destination) {
                    conflict_suffix += 1
                    conflict_suffix_str := fmt.aprintf("%d", conflict_suffix)
                    defer delete (conflict_suffix_str)
                    destination = filepath.join({cwd, strings.concatenate({os.short_stem(entry.name), " (", conflict_suffix_str, ")", os.long_ext(entry.name)})}) or_continue
                }
                #partial switch entry.type {
                case .Regular, .Symlink, .Named_Pipe, .Socket: os.copy_file(destination, entry.fullpath)
                case .Directory: os.copy_directory_all(destination, entry.fullpath)
                }
            }
            clear(&to_copy)
            file_list_refresh(&file_list)
        }
        case .D: {
            if input.mod == .Ctrl {
                file_list_advance(&file_list, term_size.h / 2)
            }
        }
        case .U: {
            if input.mod == .Ctrl {
                file_list_back(&file_list, term_size.h / 2)
            }
        }
        case .G: {
            if input.mod == .None {
                if last_keypress == .G && last_mod == .None && time.tick_lap_time(&time_from_last_keypress) <= time.Second {
                    file_list_back(&file_list, len(file_list.entries))
                }
            } else if input.mod == .Shift {
                file_list_advance(&file_list, len(file_list.entries))
            }
        }
        case .E: edit(&s, &file_list.entries[file_list.current])
        case .Space: file_list_toggle_mark(&file_list)
        case .Slash: {
            delete(search_phrase)
            search_phrase = ""
            file_list_clear_search(&file_list)
            mode = .Search
        }
        case .N: {
            if input.mod == .None {
                file_list_select_next_search_result(&file_list)
            } else if input.mod == .Shift {
                file_list_select_prev_search_result(&file_list)
            }
        }
        }

        time_from_last_keypress := time.tick_lap_time(&time_from_last_keypress)
        last_keypress = input.key
        last_mod = input.mod
    }

    file_list_destroy(&file_list)
    delete(cwd)
}
