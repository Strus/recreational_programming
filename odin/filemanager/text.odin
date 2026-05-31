package fm

import t "vendor/termcl"

draw_text :: proc(
    screen: ^t.Window,
    y, x: uint,
    text: string,
    styles: bit_set[t.Text_Style] = { .None },
    fg: t.Any_Color = nil,
    bg: t.Any_Color = nil
) {
    t.reset_styles(screen)

    t.move_cursor(screen, y, x)
    t.set_color_style(screen, fg, bg)
    t.set_text_style(screen, styles)
    t.write(screen, text)

    t.reset_styles(screen)
}

draw_textf :: proc(
    screen: ^t.Window,
    y, x: uint,
    text: string,
    args: ..any,
    styles: bit_set[t.Text_Style] = { .None },
    fg: t.Any_Color = nil,
    bg: t.Any_Color = nil
) {
    t.reset_styles(screen)

    t.move_cursor(screen, y, x)
    t.set_color_style(screen, fg, bg)
    t.set_text_style(screen, styles)
    t.writef(screen, text, ..args)

    t.reset_styles(screen)
}
