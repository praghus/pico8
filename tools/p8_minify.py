#!/usr/bin/env python3
import sys
import os

def extract_sections(lines):
    # find indices of section headers like __lua__, __gfx__, etc.
    headers = {}
    for i, ln in enumerate(lines):
        if ln.startswith("__") and ln.strip().endswith("__"):
            headers[ln.strip()] = i
    return headers


def minify_lua(text):
    out = []
    i = 0
    L = len(text)
    in_s = False
    in_d = False
    in_long = False
    long_level = 0
    in_line_comment = False
    in_block_comment = False
    while i < L:
        c = text[i]
        nc = text[i+1] if i+1 < L else ''
        # end of line comment
        if in_line_comment:
            if c == '\n':
                in_line_comment = False
                out.append(c)
            # else skip
            i += 1
            continue
        if in_block_comment:
            if c == ']' and nc == ']':
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_s:
            out.append(c)
            if c == "\\":
                # escape next char
                if i+1 < L:
                    out.append(text[i+1])
                    i += 1
            elif c == "'":
                in_s = False
            i += 1
            continue
        if in_d:
            out.append(c)
            if c == "\\":
                if i+1 < L:
                    out.append(text[i+1])
                    i += 1
            elif c == '"':
                in_d = False
            i += 1
            continue
        if in_long:
            out.append(c)
            if c == ']' and nc == ']':
                out.append(nc)
                in_long = False
                i += 2
                continue
            i += 1
            continue

        # not in any special state
        if c == '-' and nc == '-':
            # comment start
            # check for block comment --[[
            if i+2 < L and text[i+2] == '[' and (i+3 < L and text[i+3] == '['):
                in_block_comment = True
                i += 4
                continue
            else:
                in_line_comment = True
                i += 2
                continue
        if c == "'":
            in_s = True
            out.append(c)
            i += 1
            continue
        if c == '"':
            in_d = True
            out.append(c)
            i += 1
            continue
        if c == '[' and nc == '[':
            in_long = True
            out.append(c)
            out.append(nc)
            i += 2
            continue

        out.append(c)
        i += 1

    s = ''.join(out)
    # remove trailing spaces on each line and collapse multiple blank lines
    lines = s.splitlines()
    new_lines = []
    blank_run = 0
    for ln in lines:
        nln = ln.rstrip()
        if nln == '':
            blank_run += 1
            if blank_run <= 2:
                new_lines.append('')
        else:
            blank_run = 0
            new_lines.append(nln)
    return '\n'.join(new_lines) + ('\n' if s.endswith('\n') else '')


def process_cart(in_path, out_path):
    with open(in_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    headers = extract_sections(lines)
    if '__lua__' not in headers:
        print('no __lua__ section found')
        return 1
    lua_start = headers['__lua__'] + 1
    # find next section after lua
    next_idx = None
    for idx in range(lua_start, len(lines)):
        if lines[idx].startswith('__') and lines[idx].strip().endswith('__'):
            next_idx = idx
            break
    lua_lines = lines[lua_start:next_idx]
    lua_text = ''.join(lua_lines)
    orig_bytes = len(lua_text.encode('utf-8'))
    min_lua = minify_lua(lua_text)
    min_bytes = len(min_lua.encode('utf-8'))

    # produce new lines
    out_lines = []
    out_lines.extend(lines[:lua_start])
    out_lines.append(min_lua)
    out_lines.extend(lines[next_idx:])

    # write output
    with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
        f.writelines(out_lines)

    print(f'original lua bytes: {orig_bytes}')
    print(f'minified lua bytes: {min_bytes}')
    print(f'reduction: {orig_bytes-min_bytes} bytes')
    if min_bytes < orig_bytes:
        print('wrote minified cart to', out_path)
    else:
        print('minifier did not reduce size; wrote output anyway to', out_path)
    return 0

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('usage: p8_minify.py INPUT.p8 OUTPUT.p8')
        sys.exit(2)
    inp = sys.argv[1]
    outp = sys.argv[2]
    sys.exit(process_cart(inp, outp))
