package fm

import "core:os"
import "core:slice"

import t "vendor/termcl"

DEFAULT_PAGE_SIZE :: 20

File_List :: struct {
    entries: [dynamic]os.File_Info,
    selection: uint,
    page_size: uint,
}

parent_folder := os.File_Info {
    name = "..",
    type = .Directory,
}

file_list_init :: proc(file_list: ^File_List, path: string, page_size: uint = DEFAULT_PAGE_SIZE) {
    file_list.selection = 0
    file_list.page_size = page_size
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
    clear(&file_list.entries)
    file_list_init(file_list, path, file_list.page_size)
}

file_list_next :: proc(file_list: ^File_List) {
    file_list_advance(file_list, 1)
}

file_list_prev :: proc(file_list: ^File_List) {
    file_list_back(file_list, 1)
}

file_list_advance :: proc(file_list: ^File_List, step: uint) {
    file_list.selection += step
    file_list.selection = min(file_list.selection, uint(len(file_list.entries) - 1))
}

file_list_back :: proc(file_list: ^File_List, step: uint) {
    if file_list.selection <= step {
        file_list.selection = 0
        return
    }

    file_list.selection -= step
}

file_list_destroy :: proc(file_list: ^File_List) {
    delete(file_list.entries)
}

draw_file_list :: proc(file_list: ^File_List, s: ^t.Window, y, x: uint) {
    page : uint = file_list.selection / file_list.page_size
    start := page*file_list.page_size
    end := min(uint(len(file_list.entries)), start + file_list.page_size)
    longest : uint = 0
    for file_info, i in file_list.entries[start:end] {
        i := uint(i)
        bg : t.Any_Color = t.Color_8.Blue if file_list.selection == i + start else s.curr_styles.bg

        #partial switch file_info.type {
        case .Directory: {
            draw_textf(s, y + i, x, "%s", file_info.name, styles={ .Bold }, bg=bg)
        }
        case .Symlink: {
            link_path, err := os.read_link(file_info.fullpath, context.allocator)
            defer delete(link_path)
            if err == os.ERROR_NONE {
                draw_textf(s, y + i, x, "%s -> %s", file_info.name, link_path, fg=.Red, bg=bg)
                if uint(len(file_info.name) + len(link_path) + 4) > longest {
                    longest = len(file_info.name) + len(link_path) + 4
                }
            }
        }
        case: draw_textf(s, y + i, x, "%s", file_info.name, bg=bg)
        }

        if uint(len(file_info.name)) > longest {
            longest = len(file_info.name)
        }
    }

    current_len : uint = len(file_list.entries[file_list.selection].name)
    for i in 0..<(longest - current_len) {
        draw_text(s, y + file_list.selection % file_list.page_size, x + i + current_len, " ", bg=t.Color_8.Blue)
    }
}
