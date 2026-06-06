package fm

import "core:os"
import "core:slice"
import "core:strings"

import t "vendor/termcl"


METADATA_MAX_BYTES :: len("  ")

File_List :: struct {
    entries: [dynamic]os.File_Info,
    marked_files: map[^os.File_Info]bool,
    cwd: string,
    current: uint,

    y, x: uint,
    height, width: uint,
    w: t.Window,

    // search
    found_entries: map[^os.File_Info]bool,
    found_indexes: [dynamic]uint,
    current_result: int,

    _metadata_buf: [METADATA_MAX_BYTES]u8
}

parent_folder := os.File_Info {
    name = "..",
    type = .Directory,
}

file_list_init :: proc(fl: ^File_List, path: string, y, x: uint, height: Maybe(uint) = nil, width: Maybe(uint) = nil) {
    sort_file_list :: proc(a, b: os.File_Info) -> bool {
        a_dir := a.type == .Directory
        b_dir := b.type == .Directory

        if a_dir != b_dir {
            return a_dir
        }

        return a.name < b.name
    }

    fl.current = 0
    fl.cwd = strings.clone(path)
    parent_folder.fullpath = os.dir(path)
    clear(&fl.entries)
    clear(&fl.marked_files)

    fl.y = y
    fl.x = x
    term_size := t.get_term_size()
    fl.height = height.? or_else term_size.h - fl.y
    fl.width = width.? or_else term_size.w - fl.x
    fl.w = t.init_window(fl.y, fl.x, fl.height, fl.width)

    clear(&fl.found_entries)
    clear(&fl.found_indexes)
    fl.current_result = -1

    tree, tree_err := os.read_all_directory_by_path(path, context.allocator)
    defer delete(tree)
    if tree_err != os.ERROR_NONE {
        return
    }
    append(&fl.entries, parent_folder)
    append(&fl.entries, ..tree[:])
    slice.sort_by(fl.entries[1:], sort_file_list)
}

file_list_cd :: proc(fl: ^File_List, path: string) {
    file_list_init(fl, path, fl.y, fl.x)
}

file_list_refresh :: proc(fl: ^File_List) {
    c := fl.current
    file_list_init(fl, fl.cwd, fl.y, fl.x)
    fl.current = c
}

file_list_next :: proc(fl: ^File_List) {
    file_list_advance(fl, 1)
}

file_list_prev :: proc(fl: ^File_List) {
    file_list_back(fl, 1)
}

file_list_advance :: proc(fl: ^File_List, step: uint) {
    fl.current += step
    fl.current = min(fl.current, uint(len(fl.entries) - 1))
}

file_list_back :: proc(fl: ^File_List, step: uint) {
    if fl.current <= step {
        fl.current = 0
        return
    }

    fl.current -= step
}

file_list_destroy :: proc(fl: ^File_List) {
    delete(fl.entries)
    delete(fl.marked_files)
    delete(fl.cwd)
    delete(fl.found_entries)
    delete(fl.found_indexes)
    t.destroy_window(&fl.w)
}

file_list_toggle_mark :: proc(fl: ^File_List) {
    selected := &fl.entries[fl.current]
    if selected.name == parent_folder.name {
        return
    }

    if (selected in fl.marked_files) {
        delete_key(&fl.marked_files, selected)
    } else {
        fl.marked_files[selected] = true
    }
}

file_list_unmark_all :: proc(fl: ^File_List) {
    clear(&fl.marked_files)
}

file_list_draw :: proc(fl: ^File_List) {
    term_size := t.get_term_size()
    t.clear(&fl.w, .Everything)
    t.resize_window(&fl.w, term_size.h - fl.y, term_size.w - fl.x)

    page_size := fl.w.height.?
    page : uint = fl.current / page_size
    start := page * page_size
    end := min(uint(len(fl.entries)), start + page_size)
    for &file_info, i in fl.entries[start:end] {
        i := uint(i)
        fg : t.Any_Color = t.Color_8.White if fl.current == i + start else fl.w.curr_styles.fg
        bg : t.Any_Color = t.Color_RGB{50,50,50} if fl.current == i + start else fl.w.curr_styles.bg
        bg = .Yellow if &file_info in fl.found_entries && mode == .Search else bg
        metadata_string := get_metadata_string(fl, &file_info, fl.current == i + start)

        #partial switch file_info.type {
        case .Directory: {
            draw_textf(&fl.w, i, 0, "%s%s", metadata_string, file_info.name, styles={ .Bold }, fg=t.Color_RGB{125,125,125}, bg=bg)
        }
        case .Symlink: {
            link_path, err := os.read_link(file_info.fullpath, context.allocator)
            defer delete(link_path)
            if err == os.ERROR_NONE {
                fg : t.Any_Color = t.Color_8.Black if fl.current == i + start else .Red
                draw_textf(&fl.w, i, 0, "%s%s", metadata_string, file_info.name, fg=fg, bg=bg)
                draw_textf(&fl.w, i, text_width(metadata_string) + len(file_info.name), " -> %s", link_path, styles={.Italic}, fg=fg, bg=bg)
            }
        }
        case: {
            draw_textf(&fl.w, i, 0, "%s%s", metadata_string, file_info.name, fg=fg, bg=bg)
        }
        }
    }

    selected_entry := &fl.entries[fl.current]
    metadata_string := get_metadata_string(fl, selected_entry, true)
    selected_text_len : uint = len(selected_entry.name) + text_width(metadata_string)
    for i in 0..<(fl.w.width.? - selected_text_len) {
        draw_text(&fl.w, fl.current % page_size, i + selected_text_len, " ", bg=t.Color_RGB{50,50,50})
    }

    t.blit(&fl.w)
}

file_list_search :: proc(fl: ^File_List, query: string) {
    file_list_clear_search(fl)

    for &entry, i in fl.entries {
        if strings.contains(entry.name, query) {
            fl.found_entries[&entry] = true
            append(&fl.found_indexes, uint(i))
        }
    }
}

file_list_clear_search :: proc(fl: ^File_List) {
    clear(&fl.found_entries)
    clear(&fl.found_indexes)
    fl.current_result = -1
}

file_list_select_next_search_result :: proc(fl: ^File_List) {
    if len(fl.found_indexes) == 0 {
        return
    }

    fl.current_result += 1
    if fl.current_result >= len(fl.found_indexes) {
        fl.current_result = 0
    }
    fl.current = fl.found_indexes[fl.current_result]
}

file_list_select_prev_search_result :: proc(fl: ^File_List) {
    if len(fl.found_indexes) == 0 {
        return
    }

    fl.current_result -= 1
    if fl.current_result < 0 {
        fl.current_result = len(fl.found_indexes) - 1
    }
    fl.current = fl.found_indexes[fl.current_result]
}

get_metadata_string :: proc(fl: ^File_List, entry: ^os.File_Info, is_selected: bool) -> string {
    b := strings.builder_from_bytes(fl._metadata_buf[:])

    if entry in fl.marked_files {
        strings.write_string(&b, "")
    } else {
        strings.write_string(&b, " ")
    }
    strings.write_string(&b, " ")

    if entry.type == .Directory {
        strings.write_string(&b, " " if !is_selected else " ")
    } else {
        strings.write_string(&b, " ")
    }

    return strings.to_string(b)
}
