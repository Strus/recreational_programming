package fm

import t "vendor/termcl"
import tb "vendor/termcl/term"

import "core:os"

FILE_TREE_POS: uint : 2
PADDING            :: 1

tree : File_List;
cwd: string
page: uint = 0

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
}

main :: proc() {
    s := t.init_screen(tb.VTABLE)
    defer t.destroy_screen(&s)
    t.set_term_mode(&s, .Cbreak)
    t.enable_alt_buffer(true)
    t.hide_cursor(true)

    start_cwd, cwd_err := os.get_working_directory(context.allocator)
    defer delete(start_cwd)
    if cwd_err != os.ERROR_NONE {
        return
    }
    cwd = start_cwd
    term_size := t.get_term_size()
    file_list_init(&tree, cwd, term_size.h - 1 - FILE_TREE_POS)

    should_quit := false
    for !should_quit {
        t.clear(&s, .Everything)
        term_size := t.get_term_size()

        draw_textf(&s, 0, 0, "%s", cwd)
        draw_file_list(&tree, &s, FILE_TREE_POS, PADDING)
        draw_textf(&s, term_size.h - 1, 0, "current_pos: %d | page_size: %d", tree.selection, tree.page_size)

        t.blit(&s)

        input, input_ok := t.read_blocking(&s).(t.Keyboard_Input)
		if input_ok {
            #partial switch input.key {
            case .Escape: should_quit = true
            case .J: file_list_next(&tree)
            case .K: file_list_prev(&tree)
            case .H: go_to_parent()
            case .D: file_list_advance(&tree, term_size.h / 2)
            case .G: {
                if input.mod == .Shift {
                    file_list_advance(&tree, len(tree.entries))
                } else {
                    file_list_back(&tree, len(tree.entries))
                }
            }
            case .U: {
                file_list_back(&tree, term_size.h / 2)
            }
            case .L, .Enter: {
                if tree.selection == 0 {
                    go_to_parent()
                } else {
                    open(&tree.entries[tree.selection])
                }
            }
            case .E: edit(&s, &tree.entries[tree.selection])
            }
		}
    }

    file_list_destroy(&tree)
}
