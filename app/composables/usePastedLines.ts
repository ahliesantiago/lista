// Shared by any "paste a chunk of text, one line per item" flow (list
// items, masterlist quick-add). Strips common leading markers (-, *, •,
// "1.", "1)", "a.") since pasted lists very often already have them - a
// marker is only stripped when followed by whitespace, so a genuine name
// like "A1 Steak Sauce" is left untouched. Blank lines are dropped.
export function splitPastedLines(text: string): string[] {
  return text
    .split(/\r\n|\r|\n/)
    .map((line) => line.trim().replace(/^(?:[-*•◦]|\d+[.)]|[a-zA-Z][.)])\s+/, '').trim())
    .filter((line) => line.length > 0)
}
