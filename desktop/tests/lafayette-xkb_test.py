"""Validate Lafayette with libxkbcommon, without injecting desktop input.

Usage: python lafayette-xkb_test.py /path/to/libxkbcommon.so < keymap.xkb
Outputs the six display levels for each character key as JSON.
"""
import ctypes as c
import json
import sys

lib = c.CDLL(sys.argv[1])


def api(name, result, *args):
    fn = getattr(lib, "xkb_" + name)
    fn.restype, fn.argtypes = result, args
    return fn


ptr, uint = c.c_void_p, c.c_uint32
context_new = api("context_new", ptr, c.c_int)
keymap_new = api("keymap_new_from_string", ptr, ptr, c.c_char_p, c.c_int, c.c_int)
key_by_name = api("keymap_key_by_name", uint, ptr, c.c_char_p)
get_syms = api("keymap_key_get_syms_by_level", c.c_int, ptr, uint, uint, uint, c.POINTER(c.POINTER(uint)))
to_utf32 = api("keysym_to_utf32", uint, uint)
sym_name = api("keysym_get_name", c.c_int, uint, c.c_char_p, c.c_size_t)
state_new = api("state_new", ptr, ptr)
state_unref = api("state_unref", None, ptr)
update = api("state_update_key", c.c_int, ptr, uint, c.c_int)
get_sym = api("state_key_get_one_sym", uint, ptr, uint)
serialize_mods = api("state_serialize_mods", uint, ptr, c.c_int)
compose_table_new = api("compose_table_new_from_locale", ptr, ptr, c.c_char_p, c.c_int)
compose_new = api("compose_state_new", ptr, ptr, c.c_int)
compose_feed = api("compose_state_feed", c.c_int, ptr, uint)
compose_utf8 = api("compose_state_get_utf8", c.c_int, ptr, c.c_char_p, c.c_size_t)
compose_unref = api("compose_state_unref", None, ptr)

context = context_new(0)
keymap = keymap_new(context, sys.stdin.buffer.read(), 1, 0)
assert keymap, "Lafayette keymap must compile"


def key(name):
    code = key_by_name(keymap, name.encode())
    assert code != 0xFFFFFFFF, name
    return code


def tap(state, name):
    code = key(name)
    symbol = get_sym(state, code)
    update(state, code, 1)
    update(state, code, 0)
    return symbol


# All these sequences release the latch before pressing the letter.
for name, expected in [("AD02", "é"), ("AD03", "è"), ("AC01", "à"),
                       ("AB03", "ç"), ("AC03", "ê"), ("AD09", "œ")]:
    state = state_new(keymap)
    tap(state, "AC10")
    assert chr(to_utf32(tap(state, name))) == expected
    assert chr(to_utf32(tap(state, "AD03"))) == "e", "Latch must clear after one letter"
    state_unref(state)

state = state_new(keymap)
tap(state, "AC10")
update(state, key("LFSH"), 1)
assert chr(to_utf32(tap(state, "AD02"))) == "É"
update(state, key("LFSH"), 0)
update(state, key("RALT"), 1)
assert chr(to_utf32(tap(state, "AC01"))) == "{", "AltGr must retain the symbols layer"
update(state, key("RALT"), 0)
state_unref(state)

# Repeated Cmd+apostrophe must not arm Lafayette's one-shot accent layer.
for release_cmd_first in [False, True]:
    state = state_new(keymap)
    for _ in range(4):
        update(state, key("LWIN"), 1)
        assert chr(to_utf32(get_sym(state, key("AC11")))) == "'"
        update(state, key("AC11"), 1)
        for name in (["LWIN", "AC11"] if release_cmd_first else ["AC11", "LWIN"]):
            update(state, key(name), 0)
        assert serialize_mods(state, 2) == 0, "Help shortcut must not latch accents"
    assert chr(to_utf32(tap(state, "AD03"))) == "e"
    state_unref(state)

# Double latch becomes a dead diaeresis, composed by the application.
table = compose_table_new(context, b"en_US.UTF-8", 0)
assert table
compose = compose_new(table, 0)
state = state_new(keymap)
tap(state, "AC10")
compose_feed(compose, tap(state, "AC10"))
compose_feed(compose, tap(state, "AD03"))
buf = c.create_string_buffer(64)
compose_utf8(compose, buf, len(buf))
assert buf.value.decode() == "ë"
compose_unref(compose)
state_unref(state)

dead = {
    "dead_circumflex": "◌̂", "dead_grave": "◌̀", "dead_diaeresis": "◌̈",
    "dead_acute": "◌́", "dead_currency": "¤★", "dead_abovering": "◌̊",
    "dead_caron": "◌̌", "dead_abovedot": "◌̇", "dead_stroke": "◌̸",
    "dead_macron": "◌̄", "dead_doubleacute": "◌̋", "dead_tilde": "◌̃",
    "dead_belowcomma": "◌̦", "dead_ogonek": "◌̨", "dead_cedilla": "◌̧",
    "dead_breve": "◌̆", "ISO_Level5_Latch": "★", "VoidSymbol": "", "NoSymbol": "",
}


def glyph(symbol):
    buf = c.create_string_buffer(64)
    sym_name(symbol, buf, len(buf))
    name = buf.value.decode()
    if name in dead:
        return dead[name]
    value = to_utf32(symbol)
    assert value, "Unrecognized symbol: " + name
    return chr(value)


positions = {}
for prefix, labels in [("AE", "1234567890-="), ("AD", "QWERTYUIOP[]"),
                       ("AC", "ASDFGHJKL;'"), ("AB", "ZXCVBNM,./")]:
    for index, label in enumerate(labels, 1):
        positions[label] = prefix + str(index).zfill(2)
positions.update({"\\": "BKSL", "`": "TLDE"})
levels = {}
for label, name in positions.items():
    values = []
    for level in range(6):
        syms = c.POINTER(uint)()
        count = get_syms(keymap, key(name), 0, level, c.byref(syms))
        values.append(glyph(syms[0]) if count else "")
    levels[label] = values
print(json.dumps(levels, ensure_ascii=False))
