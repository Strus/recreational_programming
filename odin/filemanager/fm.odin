package fm

import t "vendor/termcl"
import tb "vendor/termcl/term"

import "core:path/filepath"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

FILE_TREE_POS: uint : 2

tree : File_List;
tree_window: t.Window
cwd: string
page: uint = 0
to_copy : [dynamic]os.File_Info

go_to_parent :: proc() {
    cwd = os.dir(cwd)
    page = 0
    file_list_cd(&tree, cwd)
}

open :: proc(file_info: ^os.File_Info) {
    if file_info.type == .Directory {
        cwd = file_info.fullpath
        file_list_cd(&tree, cwd)
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

    file_list_refresh(&tree)
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
    file_list_init(&tree, cwd, term_size.h - 1 - FILE_TREE_POS)
    tree_window = t.init_window(FILE_TREE_POS, 0, term_size.h - FILE_TREE_POS - 1, term_size.w)
    defer t.destroy_window(&tree_window)

    should_quit := false
    time_from_last_keypress := time.Tick{0}
    last_keypress: t.Key
    last_mod: t.Mod
    for !should_quit {
        term_size = t.get_term_size()
        t.resize_window(&tree_window, term_size.h - FILE_TREE_POS - 1, term_size.w)
        t.clear(&s, .Everything)
        t.clear(&tree_window, .Everything)

        draw_textf(&s, 0, 0, "%s", cwd)
        file_list_draw(&tree, &tree_window)
        draw_textf(&s, term_size.h - 1, 0, "current_pos: %d | page_size: %d", tree.current, tree.page_size)

        t.blit(&s)
        t.blit(&tree_window)

        input, input_ok := t.read_blocking(&s).(t.Keyboard_Input)
		if input_ok {
            #partial switch input.key {
            case .Q: should_quit = true
            case .J: file_list_next(&tree)
            case .K: file_list_prev(&tree)
            case .H: go_to_parent()
            case .L, .Enter: {
                open(&tree.entries[tree.current])
            }
            case .Y: {
                for entry in tree.marked_files {
                    append(&to_copy, entry^)
                }
                file_list_unmark_all(&tree)
                file_list_refresh(&tree)
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
                    os.copy_file(destination, entry.fullpath)
                }
                clear(&to_copy)
                file_list_refresh(&tree)
            }
            case .D: {
                if input.mod == .Ctrl {
                    file_list_advance(&tree, term_size.h / 2)
                }
            }
            case .U: {
                if input.mod == .Ctrl {
                    file_list_back(&tree, term_size.h / 2)
                }
            }
            case .G: {
                if input.mod == .Shift {
                    file_list_advance(&tree, len(tree.entries))
                } else if input.mod == .None {
                    if last_keypress == .G && last_mod == .None && time.tick_lap_time(&time_from_last_keypress) <= time.Second {
                        file_list_back(&tree, len(tree.entries))
                    }
                }
            }
            case .E: edit(&s, &tree.entries[tree.current])
            case .Space: file_list_toggle_mark(&tree)
            }

            time_from_last_keypress := time.tick_lap_time(&time_from_last_keypress)
            last_keypress = input.key
            last_mod = input.mod
		}
    }

    file_list_destroy(&tree)
    delete(cwd)
}
