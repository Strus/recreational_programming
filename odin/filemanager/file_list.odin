package fm

import "core:os"
import "core:slice"
import "core:unicode/utf8"
import "core:strings"

import t "vendor/termcl"


File_List :: struct {
    entries: [dynamic]os.File_Info,
    marked_files: map[^os.File_Info]bool,
    cwd: string,
    current: uint,
    page_size: uint,
}

parent_folder := os.File_Info {
    name = "..",
    type = .Directory,
}

file_list_init :: proc(file_list: ^File_List, path: string, page_size: uint) {
    if file_list.marked_files == nil {
        file_list.marked_files = make(map[^os.File_Info]bool)
    } else {
        file_list_unmark_all(file_list)
    }
    file_list.current = 0
    file_list.page_size = page_size
    file_list.cwd = strings.clone(path)
    parent_folder.fullpath = os.dir(path)
    clear(&file_list.entries)
    append(&file_list.entries, parent_folder)

    tree, tree_err := os.read_all_directory_by_path(path, context.allocator)
    defer delete(tree)
    if tree_err != os.ERROR_NONE {
        return
    }
    append(&file_list.entries, ..tree[:])

    sort_tree :: proc(a, b: os.File_Info) -> bool {
        a_dir := a.type == .Directory
        b_dir := b.type == .Directory

        if a_dir != b_dir {
            return a_dir
        }

        return a.name < b.name
    }
    slice.sort_by(file_list.entries[1:], sort_tree)
}

file_list_cd :: proc(file_list: ^File_List, path: string) {
    file_list_init(file_list, path, file_list.page_size)
}

file_list_refresh :: proc(file_list: ^File_List) {
    c := file_list.current
    file_list_init(file_list, file_list.cwd, file_list.page_size)
    file_list.current = c
}

file_list_next :: proc(file_list: ^File_List) {
    file_list_advance(file_list, 1)
}

file_list_prev :: proc(file_list: ^File_List) {
    file_list_back(file_list, 1)
}

file_list_advance :: proc(file_list: ^File_List, step: uint) {
    file_list.current += step
    file_list.current = min(file_list.current, uint(len(file_list.entries) - 1))
}

file_list_back :: proc(file_list: ^File_List, step: uint) {
    if file_list.current <= step {
        file_list.current = 0
        return
    }

    file_list.current -= step
}

file_list_destroy :: proc(file_list: ^File_List) {
    delete(file_list.entries)
    delete(file_list.marked_files)
    delete(file_list.cwd)
}

file_list_toggle_mark :: proc(file_list: ^File_List) {
    selected := &file_list.entries[file_list.current]
    if selected.name == parent_folder.name {
        return
    }

    if (selected in file_list.marked_files) {
        delete_key(&file_list.marked_files, selected)
    } else {
        file_list.marked_files[selected] = true
    }
}

file_list_unmark_all :: proc(file_list: ^File_List) {
    clear(&file_list.marked_files)
}

file_list_draw :: proc(file_list: ^File_List, s: ^t.Window) {
    page : uint = file_list.current / file_list.page_size
    start := page*file_list.page_size
    end := min(uint(len(file_list.entries)), start + file_list.page_size)
    for &file_info, i in file_list.entries[start:end] {
        i := uint(i)
        fg : t.Any_Color = t.Color_8.White if file_list.current == i + start else s.curr_styles.fg
        bg : t.Any_Color = t.Color_RGB{50,50,50} if file_list.current == i + start else s.curr_styles.bg
        metadata_string := get_metadata_string(file_list, &file_info, file_list.current == i + start)
        defer delete(metadata_string)

        #partial switch file_info.type {
        case .Directory: {
            draw_textf(s, i, 0, "%s%s", metadata_string, file_info.name, styles={ .Bold }, fg=t.Color_RGB{125,125,125}, bg=bg)
        }
        case .Symlink: {
            link_path, err := os.read_link(file_info.fullpath, context.allocator)
            defer delete(link_path)
            if err == os.ERROR_NONE {
                fg : t.Any_Color = t.Color_8.Black if file_list.current == i + start else .Red
                draw_textf(s, i, 0, "%s%s", metadata_string, file_info.name, fg=fg, bg=bg)
                draw_textf(s, i, text_width(metadata_string) + len(file_info.name), " -> %s", link_path, styles={.Italic}, fg=fg, bg=bg)
            }
        }
        case: {
            draw_textf(s, i, 0, "%s%s", metadata_string, file_info.name, fg=fg, bg=bg)
        }
        }
    }

    selected_entry := &file_list.entries[file_list.current]
    metadata_string := get_metadata_string(file_list, selected_entry, true)
    defer delete(metadata_string)
    selected_text_len : uint = len(selected_entry.name) + text_width(metadata_string)
    for i in 0..<(s.width.? - selected_text_len) {
        draw_text(s, file_list.current % file_list.page_size, i + selected_text_len, " ", bg=t.Color_RGB{50,50,50})
    }
}

get_metadata_string :: proc(file_list: ^File_List, entry: ^os.File_Info, is_selected: bool) -> string {
    b := strings.builder_make()
    defer strings.builder_destroy(&b)

    if entry in file_list.marked_files {
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

    return strings.clone(strings.to_string(b))
}

text_width :: proc(text: string) -> uint {
    _, _, width := utf8.grapheme_count(text)
    return uint(width)
}
