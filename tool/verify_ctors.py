#!/usr/bin/env python3
"""Named-argument checker for the BankSheet Flutter app.

`tool/verify_dart.py` answers "does this symbol exist and is it imported".
This answers the next question down, and the one that actually breaks builds
when screens are rewritten: **for every widget constructed in this codebase,
does the call pass named arguments the constructor accepts, and does it pass
every argument the constructor requires.**

That is the failure mode of a UI refactor. Renaming `ViewerHomeScreen` to
`HomeScreen` is caught by any grep; passing `subtitle:` to a widget that only
takes `caption:` is not, and neither is dropping a `required` parameter — both
are silent until `flutter analyze` runs, which it cannot here.

Scope, deliberately narrow so every finding is real:

  * only classes declared in `lib/` are checked — a Flutter SDK or plugin
    constructor is not in this tree, so nothing is assumed about it;
  * only constructors this script can parse unambiguously; anything with a
    shape it does not recognise is skipped rather than guessed at;
  * a call whose arguments include a spread or a conditional at the top level
    is skipped, since the argument list is not statically known.

Exit code is 1 if anything is found, so it can gate a commit.

    python3 tool/verify_ctors.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, 'lib')
TEST = os.path.join(ROOT, 'test')

problems = []


def dart_files(*roots):
    out = []
    for r in roots:
        for dirpath, _, names in os.walk(r):
            for n in names:
                if n.endswith('.dart'):
                    out.append(os.path.join(dirpath, n))
    return sorted(out)


def strip_comments_and_strings(text):
    """Blank out comments and string bodies, preserving offsets and newlines.

    Offsets are preserved so a match position still maps to the right line.
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != '\n':
                    out[k] = ' '
            i = j
        elif c in '\'"':
            triple = text[i:i + 3]
            if triple in ("'''", '"""'):
                j = text.find(triple, i + 3)
                j = n if j < 0 else j + 3
            else:
                j = i + 1
                while j < n:
                    if text[j] == '\\':
                        j += 2
                        continue
                    if text[j] == c or text[j] == '\n':
                        j += 1
                        break
                    j += 1
            for k in range(i, min(j, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j
        else:
            i += 1
    return ''.join(out)


def match_paren(src, open_idx):
    """Index just past the ')' matching the '(' at open_idx, or -1."""
    depth = 0
    i = open_idx
    n = len(src)
    while i < n:
        c = src[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return -1


def split_top_level(args):
    """Split an argument list on commas that are not inside brackets.

    Angle brackets need care and getting them wrong silently corrupts every
    result downstream. Dart argument lists are full of `=>` — every closure and
    every switch-expression arm — and counting that `>` as a closing generic
    drives the depth negative, at which point nested named arguments start
    looking top level and the checker reports parameters the caller never
    passed. But generics genuinely do appear in argument position
    (`<String, String>{...}`), and their commas must not split either.

    So: `<` opens a generic only where one can legally start, and `>` closes one
    only when a generic is actually open and the character is not part of `=>`,
    `>=` or `>>`.
    """
    parts, depth, angle, buf = [], 0, 0, []
    prev = ''
    n = len(args)
    for i, ch in enumerate(args):
        nxt = args[i + 1] if i + 1 < n else ''
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        elif ch == '<' and (prev.isalnum() or prev in '_,({[: ') and nxt != '=':
            angle += 1
        elif ch == '>' and angle > 0 and prev != '=' and nxt != '=':
            angle -= 1

        if ch == ',' and depth == 0 and angle == 0:
            parts.append(''.join(buf))
            buf = []
        else:
            buf.append(ch)

        if not ch.isspace():
            prev = ch
    if ''.join(buf).strip():
        parts.append(''.join(buf))
    return parts


# --------------------------------------------------------------- constructors

CLASS_RE = re.compile(
    r'\bclass\s+([A-Z]\w*)\b[^{]*\{', re.S)

# `const Foo({` / `Foo({` / `const Foo(this.x, {` / `Foo._(...)`
CTOR_RE_TMPL = r'(?:const\s+)?{cls}\s*(?:\.\s*(\w+)\s*)?\('


def parse_classes(files):
    """Returns (classes, decl_spans).

    `decl_spans` maps a file path to the character ranges occupied by
    constructor *declarations*, so the call-site pass can skip them — otherwise
    `const AppCard({required this.child})` is read as a call to `AppCard` with
    no arguments, and every widget in the project reports itself missing its own
    required parameters.
    """
    classes = {}
    decl_spans = {}
    for path in files:
        raw = open(path, encoding='utf-8').read()
        src = strip_comments_and_strings(raw)

        for m in CLASS_RE.finditer(src):
            cls = m.group(1)
            body_start = m.end() - 1
            body_end = match_paren(src, body_start)
            if body_end < 0:
                continue
            body = src[body_start:body_end]

            # Every constructor declaration in the body is recorded so the
            # call-site pass can skip it, but only the unnamed one defines the
            # signature a bare `Foo(` call must satisfy.
            unnamed = None
            for c in re.finditer(
                    CTOR_RE_TMPL.format(cls=re.escape(cls)), body):
                o = body.index('(', c.start())
                e = match_paren(body, o)
                if e < 0:
                    continue
                decl_spans.setdefault(path, []).append(
                    (body_start + c.start(), body_start + e))
                if c.group(1) is None and unnamed is None:
                    unnamed = (o, e)

            if unnamed is None:
                continue
            open_idx, close_idx = unnamed
            params = body[open_idx + 1:close_idx - 1]

            named, required, positional = set(), set(), 0
            brace = params.find('{')
            head = params[:brace] if brace >= 0 else params
            for p in split_top_level(head):
                if p.strip():
                    positional += 1

            if brace >= 0:
                tail = params[brace + 1:params.rfind('}')]
                for p in split_top_level(tail):
                    p = p.strip()
                    if not p:
                        continue
                    is_required = p.startswith('required ')
                    p = p[len('required '):] if is_required else p
                    # `this.foo`, `super.key`, `Widget child`, `int x = 3`
                    p = p.split('=')[0].strip()
                    name = p.split('.')[-1].split()[-1].strip()
                    if not re.fullmatch(r'\w+', name):
                        continue
                    named.add(name)
                    if is_required:
                        required.add(name)

            classes[cls] = {
                'named': named,
                'required': required,
                'positional': positional,
                'file': os.path.relpath(path, ROOT),
            }
    return classes, decl_spans


# ---------------------------------------------------------------- call sites

CALL_RE = re.compile(r'\b([A-Z]\w*)\s*\(')

# Constructed by the framework, by a factory, or in a shape this cannot read.
SKIP_CALLS = {'Key', 'ValueKey', 'GlobalKey', 'Future', 'Stream', 'List', 'Map',
              'Set', 'String', 'Uri', 'Duration', 'DateTime', 'Exception'}


def check_calls(files, classes, decl_spans):
    for path in files:
        raw = open(path, encoding='utf-8').read()
        src = strip_comments_and_strings(raw)
        rel = os.path.relpath(path, ROOT)
        spans = decl_spans.get(path, [])

        for m in CALL_RE.finditer(src):
            cls = m.group(1)
            if cls in SKIP_CALLS or cls not in classes:
                continue
            # A constructor declaration is not a call to itself.
            if any(a <= m.start() < b for a, b in spans):
                continue
            # `class Foo(` never happens, but `extends Foo(` and a declaration
            # would both false-positive; skip anything preceded by a keyword.
            before = src[max(0, m.start() - 12):m.start()].rstrip()
            if before.endswith(('class', 'extends', 'implements', 'with',
                                'is', 'as')):
                continue

            open_idx = m.end() - 1
            close_idx = match_paren(src, open_idx)
            if close_idx < 0:
                continue
            args = src[open_idx + 1:close_idx - 1]

            spec = classes[cls]
            line = src.count('\n', 0, m.start()) + 1

            supplied, positional, unreadable = set(), 0, False
            for arg in split_top_level(args):
                a = arg.strip()
                if not a:
                    continue
                # A Dart 3 object pattern — `case PurchaseGranted(:final id)`
                # inside a switch — is not a constructor call and has no
                # obligation to supply required parameters.
                if a.startswith(':') or re.match(r'^(final|var)\b', a):
                    unreadable = True
                    break
                if a.startswith('...'):
                    unreadable = True
                    break
                am = re.match(r'^(\w+)\s*:(?!:)', a)
                if am:
                    supplied.add(am.group(1))
                else:
                    positional += 1

            if unreadable:
                continue

            unknown = supplied - spec['named']
            if unknown:
                problems.append(
                    f'{rel}:{line}  {cls}(...) does not accept '
                    f'{", ".join(sorted(unknown))}  '
                    f'[declared in {spec["file"]}]')

            missing = spec['required'] - supplied
            if missing:
                problems.append(
                    f'{rel}:{line}  {cls}(...) is missing required '
                    f'{", ".join(sorted(missing))}  '
                    f'[declared in {spec["file"]}]')

            if positional > spec['positional']:
                problems.append(
                    f'{rel}:{line}  {cls}(...) takes {spec["positional"]} '
                    f'positional argument(s), {positional} given  '
                    f'[declared in {spec["file"]}]')


def main():
    files = dart_files(LIB, TEST)
    classes, decl_spans = parse_classes(files)
    check_calls(files, classes, decl_spans)

    print(f'{len(classes)} project classes parsed, '
          f'{len(files)} files checked')
    for p in problems:
        print('  E ' + p)
    print(f'CONSTRUCTOR ERRORS: {len(problems)}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
