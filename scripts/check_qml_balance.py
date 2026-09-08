# 简易 QML/JS 括号配平检查（忽略字符串与注释）
import io, os

def strip_qml(s):
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == '/' and i + 1 < n and s[i + 1] == '/':
            while i < n and s[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and s[i + 1] == '*':
            i += 2
            while i + 1 < n and not (s[i] == '*' and s[i + 1] == '/'):
                i += 1
            i += 2
            continue
        if c in '"\'':
            q = c
            i += 1
            while i < n and s[i] != q:
                if s[i] == '\\':
                    i += 1
                i += 1
            i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)

root = r'e:\LeLeDaiPao\app\qml'
bad = 0
for dirpath, _, files in os.walk(root):
    for f in files:
        if not f.endswith(('.qml', '.js')):
            continue
        p = os.path.join(dirpath, f)
        s = strip_qml(io.open(p, encoding='utf-8').read())
        bal = {'{': 0, '}': 0, '(': 0, ')': 0, '[': 0, ']': 0}
        for c in s:
            if c in bal:
                bal[c] += 1
        for a, b in [('{', '}'), ('(', ')'), ('[', ']')]:
            if bal[a] != bal[b]:
                print(os.path.relpath(p, root) + ': ' + a + '=' + str(bal[a]) + ' ' + b + '=' + str(bal[b]))
                bad += 1
                break
if bad == 0:
    print('所有 QML/JS 文件括号配平 OK')
else:
    print(str(bad) + ' 个文件括号不平衡')
