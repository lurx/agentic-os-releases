# Agentic OS — הורדות

גרסת אלפא של Agentic OS, לחברי הצוות שבודקים אותה.

**דף ההורדה: https://lurx.github.io/agentic-os-releases/**

הקבצים עצמם יושבים תחת [Releases](https://github.com/lurx/agentic-os-releases/releases).
הקוד עצמו נמצא במאגר פרטי; כאן רק ההתקנות ודף ההורדה.

## מה יש בכל גרסה

| קובץ | מערכת | גודל |
| --- | --- | --- |
| `AgenticOS-<version>-arm64.dmg` | macOS על שבבי Apple (M1 ומעלה) | ~200MB |
| `AgenticOS Setup <version>.exe` | Windows 10/11 (x64 + ARM64) | ~180MB |

ההתקנה תופסת בערך חצי ג'יגה על הדיסק.

## עדכון גרסה

מריצים את קובץ ההתקנה החדש מעל הקיים. אין צורך להסיר קודם, וגם התיקייה `~/AgenticOS` נשארת במקומה — כל הסוכנים, הזיכרון והתוצרים נשמרים.

## איך מעלים גרסה חדשה (לצוות הפיתוח)

```bash
npm run dist:mac   # יוצר release/AgenticOS-<version>-arm64.dmg
npm run dist:win   # יוצר "release/AgenticOS Setup <version>.exe"

gh release create v<version>-alpha \
  --repo lurx/agentic-os-releases \
  --title "Agentic OS <version> — אלפא" \
  --notes-file notes.md \
  "app/release/AgenticOS-<version>-arm64.dmg" \
  "app/release/AgenticOS Setup <version>.exe"
```

דף ההורדה (`index.html`) מושך את הגרסה האחרונה מ-API של GitHub, ולכן הוא לא דורש עדכון בכל פעם.
