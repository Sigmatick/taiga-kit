// Markdown → .docx для раздаточных документов кита.
// Берётся ровно то, что встречается в наших файлах: заголовки, абзацы,
// таблицы, блоки кода, цитаты, жирный и моноширинный текст.
const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell,
  WidthType, ShadingType, BorderStyle, PageOrientation, ExternalHyperlink,
} = require("docx");

const [, , SRC, OUT, TITLE] = process.argv;
const md = fs.readFileSync(SRC, "utf8").split("\n");

const PAGE_W = 11906, MARGIN = 1134;          // A4 книжная, поля 2 см
const CONTENT = PAGE_W - MARGIN * 2;

// Разбор строки на куски: **жирный**, `код`, [ссылка](адрес), остальное.
// Ссылку на соседний файл делать гиперссылкой бессмысленно — в выданном
// документе её некуда вести, поэтому остаётся только подпись.
function runs(text, base = {}) {
  const out = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\([^)]+\))/g;
  let i = 0, m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > i) out.push(new TextRun({ ...base, text: text.slice(i, m.index) }));
    const t = m[0];
    if (t.startsWith("**")) {
      out.push(new TextRun({ ...base, text: t.slice(2, -2), bold: true }));
    } else if (t.startsWith("`")) {
      out.push(new TextRun({ ...base, text: t.slice(1, -1), font: "Menlo", size: 19 }));
    } else {
      const lm = t.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
      const [, label, href] = lm;
      out.push(/^https?:/.test(href)
        ? new ExternalHyperlink({ link: href, children: [new TextRun({
            ...base, text: label, style: "Hyperlink" })] })
        : new TextRun({ ...base, text: label, font: "Menlo", size: 19 }));
    }
    i = m.index + t.length;
  }
  if (i < text.length) out.push(new TextRun({ ...base, text: text.slice(i) }));
  return out.length ? out : [new TextRun({ ...base, text: "" })];
}

const para = (text, o = {}) => new Paragraph({
  children: runs(text), spacing: { after: 120, line: 276 }, ...o,
});

function codeBlock(lines) {
  return lines.map((l, i) => new Paragraph({
    children: [new TextRun({ text: l || " ", font: "Menlo", size: 18 })],
    shading: { type: ShadingType.CLEAR, fill: "F2F2F2" },
    spacing: { before: i === 0 ? 80 : 0, after: i === lines.length - 1 ? 160 : 0 },
    indent: { left: 170 },
  }));
}

function table(rows) {
  const cells = rows.map(r => r.replace(/^\||\|$/g, "").split("|").map(x => x.trim()));
  const head = cells[0], body = cells.slice(2);     // вторая строка — разделитель
  const n = head.length;
  // Ширины обязаны быть в DXA и на таблице, и в каждой ячейке:
  // проценты ломаются в Google Docs.
  const w = Array(n).fill(Math.floor(CONTENT / n));
  const mk = (txt, bold) => new TableCell({
    width: { size: w[0], type: WidthType.DXA },
    shading: bold ? { type: ShadingType.CLEAR, fill: "EDEDED" } : undefined,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    children: [new Paragraph({ children: runs(txt, bold ? { bold: true } : {}),
                               spacing: { after: 0 } })],
  });
  return new Table({
    columnWidths: w,
    width: { size: CONTENT, type: WidthType.DXA },
    rows: [new TableRow({ children: head.map(h => mk(h, true)), tableHeader: true }),
           ...body.map(r => new TableRow({
             children: Array.from({ length: n }, (_, i) => mk(r[i] ?? "", false)) }))],
  });
}

const kids = [];
for (let i = 0; i < md.length; i++) {
  const ln = md[i];
  if (ln.startsWith("```")) {                         // блок кода
    const buf = [];
    while (++i < md.length && !md[i].startsWith("```")) buf.push(md[i]);
    kids.push(...codeBlock(buf)); continue;
  }
  if (ln.startsWith("|")) {                           // таблица
    const buf = [];
    while (i < md.length && md[i].startsWith("|")) buf.push(md[i++]);
    i--;
    kids.push(table(buf));
    kids.push(new Paragraph({ text: "", spacing: { after: 160 } }));
    continue;
  }
  const h = ln.match(/^(#{1,4}) (.*)$/);
  if (h) {
    const lvl = [HeadingLevel.TITLE, HeadingLevel.HEADING_1,
                 HeadingLevel.HEADING_2, HeadingLevel.HEADING_3][h[1].length - 1];
    kids.push(new Paragraph({ children: runs(h[2]), heading: lvl,
                              spacing: { before: 280, after: 140 } }));
    continue;
  }
  if (ln.startsWith("> ")) {
    kids.push(new Paragraph({
      children: runs(ln.slice(2), { italics: true }),
      indent: { left: 340 }, spacing: { after: 120 },
      border: { left: { style: BorderStyle.SINGLE, size: 12, color: "BBBBBB", space: 8 } },
    }));
    continue;
  }
  const li = ln.match(/^\s*[-*] (.*)$/);
  if (li) { kids.push(para(li[1], { bullet: { level: 0 } })); continue; }
  if (ln.trim() === "") continue;                     // пустые строки — не абзацы
  if (/^-{3,}$/.test(ln.trim())) {                    // горизонтальная черта
    kids.push(new Paragraph({ text: "", spacing: { after: 80 },
      border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: "CCCCCC" } } }));
    continue;
  }
  kids.push(para(ln));
}

const doc = new Document({
  creator: "taiga-kit", title: TITLE || "Taiga",
  styles: { default: { document: { run: { font: "Calibri", size: 22 } } } },
  sections: [{
    properties: { page: { size: { width: PAGE_W, height: 16838,
                                  orientation: PageOrientation.PORTRAIT },
                          margin: { top: MARGIN, bottom: MARGIN,
                                    left: MARGIN, right: MARGIN } } },
    children: kids,
  }],
});
Packer.toBuffer(doc).then(b => { fs.writeFileSync(OUT, b);
  console.log("записано:", OUT, b.length, "байт"); });
