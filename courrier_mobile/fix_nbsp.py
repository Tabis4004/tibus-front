path = "android/app/src/main/kotlin/com/tibus/courrier/printer/P3PrinterModule.kt"
with open(path, encoding="utf-8") as f:
    content = f.read()

broken = ".replace(' ', ' ')"
fixed = ".replace('\\u00A0', ' ')"
count = content.count(broken)
content = content.replace(broken, fixed)
with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("replaced", count, "occurrences")
