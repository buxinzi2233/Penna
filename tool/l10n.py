"""界面多语言的辅助脚本(见 lib/l10n/l10n.dart)。

  python tool/l10n.py list  <文件...>   列出文件里还没包 tr() 的中文字符串(带行号)
  python tool/l10n.py wrap  <文件...>   把这些字符串包成 tr('原文', [参数]);用 --skip 行号,... 跳过某几行
  python tool/l10n.py keys              列出 lib 里所有 tr() 的原文,以及各语言表里还缺的

插值会变成占位符:'第 $n 页' → tr('第 {0} 页', [n])。改完要 dart analyze:
放进 tr() 的字符串不再是常量,外层的 const 要去掉(scratch 里有 decon 脚本的思路:按报错位置删 const)。
"""
import re
import sys
import pathlib

HAN = re.compile(r'[぀-ヿ一-鿿＀-￯　-〿]')


def tokens(src):
    """逐个找出字符串字面量:(起点, 终点, 引号, 是否 raw, 片段列表)。片段是 ('text', 原样文字) 或 ('expr', 表达式源码)。跳过注释。"""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            i = src.find('\n', i)
            if i < 0:
                return
            continue
        if src.startswith('/*', i):
            i = src.find('*/', i) + 2
            continue
        raw = False
        j = i
        if c in 'rR' and i + 1 < n and src[i + 1] in '\'"' and not (src[i - 1].isalnum() or src[i - 1] == '_'):
            raw = True
            j = i + 1
        if src[j] in '\'"' and (raw or j == i):
            q = src[j] * 3 if src.startswith(src[j] * 3, j) else src[j]
            k = j + len(q)
            parts, buf = [], []
            while k < n and not src.startswith(q, k):
                ch = src[k]
                if ch == '\\' and not raw:
                    buf.append(src[k:k + 2])
                    k += 2
                    continue
                if ch == '$' and not raw:
                    if buf:
                        parts.append(('text', ''.join(buf)))
                        buf = []
                    if src[k + 1] == '{':
                        depth, m = 1, k + 2
                        while depth:
                            if src[m] == '{':
                                depth += 1
                            elif src[m] == '}':
                                depth -= 1
                            elif src[m] in '\'"':
                                # 表达式里的字符串:跳到它结束
                                qq = src[m]
                                m += 1
                                while src[m] != qq:
                                    m += 2 if src[m] == '\\' else 1
                            m += 1
                        parts.append(('expr', src[k + 2:m - 1]))
                        k = m
                    else:
                        m = k + 1
                        while m < n and (src[m].isalnum() or src[m] == '_'):
                            m += 1
                        parts.append(('expr', src[k + 1:m]))
                        k = m
                    continue
                buf.append(ch)
                k += 1
            if buf:
                parts.append(('text', ''.join(buf)))
            end = k + len(q)
            yield (i, end, q, raw, parts)
            i = end
            continue
        i += 1


def groups(src):
    """相邻的字面量('a' 'b')算一组。"""
    cur = []
    for t in tokens(src):
        if cur and src[cur[-1][1]:t[0]].strip() == '':
            cur.append(t)
        else:
            if cur:
                yield cur
            cur = [t]
    if cur:
        yield cur


def has_han(g):
    # raw 字符串(正则)不翻译。
    if any(t[3] for t in g):
        return False
    return any(HAN.search(v) for t in g for kind, v in t[4] if kind == 'text')


def wrapped(src, g):
    before = src[:g[0][0]].rstrip()
    return before.endswith('tr(')


def single(q, text):
    """把一段字面量的原样文字改写成单引号里能放的样子。"""
    if q in ('"', '"""'):
        text = text.replace("\\\"", '"').replace("'", "\\'")
    if len(q) == 3:
        text = text.replace('\n', '\\n')
    return text


def convert(src, g):
    pieces, args = [], []
    for (_, _, q, raw, parts) in g:
        out = []
        for kind, v in parts:
            if kind == 'text':
                out.append(single(q, v))
            else:
                if v in args:
                    out.append('{%d}' % args.index(v))
                else:
                    out.append('{%d}' % len(args))
                    args.append(v)
        pieces.append("'" + ''.join(out) + "'")
    inner = '\n'.join(pieces) if len(pieces) > 1 else pieces[0]
    if args:
        return 'tr(%s, [%s])' % (inner, ', '.join(args))
    return 'tr(%s)' % inner


def line_of(src, i):
    return src.count('\n', 0, i) + 1


def cmd_list(files):
    for f in files:
        src = pathlib.Path(f).read_text(encoding='utf-8')
        for g in groups(src):
            if has_han(g) and not wrapped(src, g):
                print('%s:%d: %s' % (f, line_of(src, g[0][0]), convert(src, g)))


def cmd_wrap(files, skip):
    for f in files:
        p = pathlib.Path(f)
        src = p.read_text(encoding='utf-8')
        edits = []
        for g in groups(src):
            if has_han(g) and not wrapped(src, g) and line_of(src, g[0][0]) not in skip.get(p.name, ()):
                edits.append((g[0][0], g[-1][1], convert(src, g)))
        for a, b, text in reversed(edits):
            src = src[:a] + text + src[b:]
        if edits and "l10n/l10n.dart'" not in src:
            depth = len(p.relative_to('lib').parts) - 1
            imp = "import '%sl10n/l10n.dart';\n" % ('../' * depth)
            m = list(re.finditer(r"^import '[^']*';\n", src, re.M))
            pos = m[-1].end() if m else 0
            src = src[:pos] + imp + src[pos:]
        p.write_text(src, encoding='utf-8', newline='')
        print(f, len(edits))


def tr_keys():
    keys = {}
    for p in pathlib.Path('lib').rglob('*.dart'):
        if p.parts[1] == 'l10n':
            continue
        src = p.read_text(encoding='utf-8')
        for g in groups(src):
            if wrapped(src, g):
                key = ''.join(
                    v.replace("\\'", "'").replace('\\n', '\n').replace('\\$', '$').replace('\\\\', '\\')
                    if kind == 'text' else '?'
                    for t in g for kind, v in t[4])
                keys.setdefault(key, str(p))
    return keys


def cmd_keys():
    keys = tr_keys()
    print('keys:', len(keys))
    for lang in ('zh_hant', 'en', 'ja'):
        src = pathlib.Path('lib/l10n/l10n_%s.dart' % lang).read_text(encoding='utf-8')
        have = set()
        for g in groups(src):
            have.add(''.join(v.replace("\\'", "'").replace('\\n', '\n').replace('\\$', '$').replace('\\\\', '\\')
                             for t in g for kind, v in t[4] if kind == 'text'))
        missing = [k for k in keys if k not in have]
        print(lang, 'missing', len(missing))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    cmd, *rest = sys.argv[1:]
    skip = {}
    if '--skip' in rest:
        i = rest.index('--skip')
        for item in rest[i + 1].split(';'):
            name, lines = item.split(':')
            skip[name] = {int(x) for x in lines.split(',')}
        rest = rest[:i] + rest[i + 2:]
    {'list': lambda: cmd_list(rest), 'wrap': lambda: cmd_wrap(rest, skip), 'keys': cmd_keys}[cmd]()
