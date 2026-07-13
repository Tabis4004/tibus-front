path = "android/app/src/main/kotlin/com/tibus/courrier/printer/P3PrinterModule.kt"
with open(path, "rb") as f:
    data = f.read()

# Match the various broken forms produced during copy: a literal ASCII
# space (0x20) or an actual NBSP byte sequence (0xC2 0xA0 in UTF-8) sitting
# where the Kotlin escape sequence   should be, inside .replace(...) or
# .replace("...") calls. We rebuild the exact original patterns explicitly.
replacements = [
    (b".replace('\xc2\xa0', ' ')", b".replace('\\u00A0', ' ')"),
    (b".replace(' ', ' ')", b".replace('\\u00A0', ' ')"),
    (b'.replace("\xc2\xa0", " ")', b'.replace("\\u00A0", " ")'),
    (b'.replace(" ", " ")', b'.replace("\\u00A0", " ")'),
]

total = 0
for old, new in replacements:
    n = data.count(old)
    if n:
        data = data.replace(old, new)
        total += n

with open(path, "wb") as f:
    f.write(data)

print("fixed", total, "occurrences")
