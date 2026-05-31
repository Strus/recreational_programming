package fm

import t "vendor/termcl"
import tb "vendor/termcl/term"

import "core:os"
import "core:slice"

FILE_TREE_POS : uint : 2
PADDING             :: 1

cwd : string
current_cursor_pos : uint = FILE_TREE_POS
page : uint = 0

go_to_parent :: proc() {
    cwd = os.dir(cwd)
    page = 0
}

open :: proc(file_info : ^os.File_Info) {
    if file_info.type == .Directory {
        cwd = file_info.fullpath
        current_cursor_pos = FILE_TREE_POS + 1
        return
    }

    desc := os.Process_Desc {
		command = []string{"open", file_info.fullpath},
	}

	p, err := os.process_start(desc)
}

edit :: proc(s : ^t.Screen, file_info : ^os.File_Info) {
    bring_back_fm :: proc(s : ^t.Screen) {
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

    start_cwd, cwd_err := os.get_working_directory(context.allocator)
    defer delete(start_cwd)
    if cwd_err != os.ERROR_NONE {
        return
    }
    cwd = start_cwd

    should_quit := false
    for !should_quit {
        t.clear(&s, .Everything)

        tree, tree_err := os.read_all_directory_by_path(cwd, context.allocator)
        defer delete(tree)
        if tree_err != os.ERROR_NONE {
            return
        }

        sort_tree :: proc(a, b: os.File_Info) -> bool {
            a_dir := a.type == .Directory
            b_dir := b.type == .Directory

            if a_dir != b_dir {
                return a_dir
            }

            return a.name < b.name
        }
        slice.sort_by(tree, sort_tree)

        term_size := t.get_term_size()
        if current_cursor_pos < FILE_TREE_POS  {
            current_cursor_pos = FILE_TREE_POS
            if page != 0 {
                page -= 1
            }
        } else if current_cursor_pos > FILE_TREE_POS + len(tree) {
            current_cursor_pos = FILE_TREE_POS + len(tree)
        } else if current_cursor_pos > term_size.h - 1 {
            current_cursor_pos = FILE_TREE_POS
            page += 1
        }

        t.move_cursor(&s, 0, 0)
        t.writef(&s, "%s:", cwd)

        t.move_cursor(&s, FILE_TREE_POS, PADDING)
        t.set_text_style(&s, { .Bold })
        t.writef(&s, "..")
        t.reset_styles(&s)

        for file_info, i in tree[page*term_size.h:] {
            i := cast(uint)i
            if i + FILE_TREE_POS > term_size.h - FILE_TREE_POS {
                break
            }

            t.move_cursor(&s, FILE_TREE_POS + 1 + i, PADDING)
            #partial switch file_info.type {
            case .Directory: {
                t.set_text_style(&s, { .Bold })
                t.writef(&s, "%s", file_info.name)
            }
            case .Symlink: {
                t.set_color_style(&s, .Red, nil)
                link_path, err := os.read_link(file_info.fullpath, context.allocator)
                defer delete(link_path)
                if err == os.ERROR_NONE {
                    t.writef(&s, "%s -> %s", file_info.name, link_path)
                }
            }
            // case: t.writef(&s, "%.1fM %s", cast(f32)file_info.size/1024/1024, file_info.name)
            case: t.writef(&s, "%s", file_info.name)
            }
            t.reset_styles(&s)
        }

        t.move_cursor(&s, term_size.h - 1, 0)
        t.writef(&s, "current_pos: %d | page: %d", current_cursor_pos, page)

        t.move_cursor(&s, current_cursor_pos, PADDING)
        t.blit(&s)

        input, input_ok := t.read_blocking(&s).(t.Keyboard_Input)
		if input_ok {
            #partial switch input.key {
            case .Escape: should_quit = true
            case .J: current_cursor_pos += 1
            case .K: current_cursor_pos -= 1
            case .H: go_to_parent()
            case .D: current_cursor_pos += term_size.h / 2
            case .U: {
                if cast(int)current_cursor_pos - cast(int)term_size.h > 0 {
                    current_cursor_pos -= term_size.h / 2
                } else {
                    current_cursor_pos = FILE_TREE_POS
                }
            }
            case .L, .Enter: {
                if current_cursor_pos == FILE_TREE_POS {
                    go_to_parent()
                } else {
                    open(&tree[current_cursor_pos - FILE_TREE_POS - 1])
                }
            }
            case .E: edit(&s, &tree[current_cursor_pos - FILE_TREE_POS - 1])
            }
		}
    }
}
