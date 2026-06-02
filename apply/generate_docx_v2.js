const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  ImageRun, Header, Footer, AlignmentType, LevelFormat,
  HeadingLevel, BorderStyle, WidthType, ShadingType,
  PageNumber, PageBreak,
} = require("docx");

const PAGE_W = 11906;
const PAGE_H = 16838;
const MARGIN_TOP = 1440;
const MARGIN_BOT = 1440;
const MARGIN_LEFT = 1800;
const MARGIN_RIGHT = 1800;
const CONTENT_W = PAGE_W - MARGIN_LEFT - MARGIN_RIGHT;

const FONT_SONG = "\u5B8B\u4F53";
const FONT_HEI = "\u9ED1\u4F53";
const FONT_KAI = "\u6977\u4F53";

const SIZE_BODY = 24;
const SIZE_TITLE = 32;
const SIZE_H1 = 28;
const SIZE_H2 = 26;
const SIZE_REF = 21;
const SIZE_CAPTION = 21;
const SIZE_TABLE = 21;
const LINE_SPACING = 360;

const BASE = "/Users/qiujingyi.7/ssvep/apply";
const archImg = fs.readFileSync(path.join(BASE, "arch_diagram.png"));
const hwImg = fs.readFileSync(path.join(BASE, "hardware_photo.png"));
const techImg = fs.readFileSync(path.join(BASE, "techflow_diagram.png"));

const ARCH_DISP_W = 480;
const ARCH_DISP_H = Math.round(480 * 2282 / 2368);
const HW_DISP_W = 360;
const HW_DISP_H = Math.round(360 * 2339 / 1654);
const TECH_DISP_W = 520;
const TECH_DISP_H = Math.round(520 * 170 / 2768);

function bodyPara(runs, opts) {
  opts = opts || {};
  return new Paragraph({
    spacing: { before: 60, after: 60, line: LINE_SPACING },
    indent: opts.noIndent ? undefined : { firstLine: 480 },
    alignment: opts.alignment,
    children: Array.isArray(runs) ? runs : [runs],
  });
}

function bt(text, opts) {
  opts = opts || {};
  return new TextRun({
    text: text,
    font: FONT_SONG,
    size: SIZE_BODY,
    bold: opts.bold,
    italics: opts.italics,
    superScript: opts.superScript,
  });
}

function supRef(text) { return bt(text, { superScript: true }); }

function titlePara(text) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 600, after: 400, line: 480 },
    children: [new TextRun({ text, font: FONT_HEI, size: SIZE_TITLE, bold: true })],
  });
}

function h1(text) {
  return new Paragraph({
    spacing: { before: 360, after: 200, line: LINE_SPACING },
    children: [new TextRun({ text, font: FONT_HEI, size: SIZE_H1, bold: true })],
  });
}

function h2(text) {
  return new Paragraph({
    spacing: { before: 280, after: 160, line: LINE_SPACING },
    children: [new TextRun({ text, font: FONT_HEI, size: SIZE_H2, bold: true })],
  });
}

function caption(text) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 100, after: 200 },
    children: [new TextRun({ text, font: FONT_KAI, size: SIZE_CAPTION })],
  });
}

function refPara(text) {
  return new Paragraph({
    spacing: { before: 40, after: 40, line: 300 },
    indent: { left: 480, hanging: 480 },
    children: [new TextRun({ text, font: FONT_SONG, size: SIZE_REF })],
  });
}

function placeholder(text) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 200, after: 200 },
    children: [new TextRun({ text, font: FONT_SONG, size: SIZE_BODY, color: "888888" })],
  });
}

function imgPara(data, w, h, alt) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 200, after: 0 },
    children: [new ImageRun({
      type: "png", data, transformation: { width: w, height: h },
      altText: { title: alt, description: alt, name: alt },
    })],
  });
}

var thinBorder = { style: BorderStyle.SINGLE, size: 1, color: "999999" };
var cellB = { top: thinBorder, bottom: thinBorder, left: thinBorder, right: thinBorder };
var cellM = { top: 60, bottom: 60, left: 100, right: 100 };

function hCell(text, w) {
  return new TableCell({
    borders: cellB, width: { size: w, type: WidthType.DXA },
    shading: { fill: "E8F0FE", type: ShadingType.CLEAR },
    margins: cellM, verticalAlign: "center",
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 40, after: 40 },
      children: [new TextRun({ text, font: FONT_SONG, size: SIZE_TABLE, bold: true })],
    })],
  });
}

function dCell(text, w) {
  var align = (text.length > 15) ? AlignmentType.LEFT : AlignmentType.CENTER;
  return new TableCell({
    borders: cellB, width: { size: w, type: WidthType.DXA },
    margins: cellM, verticalAlign: "center",
    children: [new Paragraph({
      alignment: align,
      spacing: { before: 40, after: 40 },
      children: [new TextRun({ text, font: FONT_SONG, size: SIZE_TABLE })],
    })],
  });
}

function mkTable(headers, rows, cw) {
  return new Table({
    width: { size: cw.reduce(function(a,b){return a+b},0), type: WidthType.DXA },
    columnWidths: cw,
    rows: [
      new TableRow({ children: headers.map(function(h,idx){ return hCell(h, cw[idx]); }) }),
    ].concat(rows.map(function(row){
      return new TableRow({ children: row.map(function(c,idx){ return dCell(c, cw[idx]); }) });
    })),
  });
}

// Parse inline text with superscript citations
function parseInline(text) {
  var runs = [];
  var re = /\[(\d+)\]/g;
  var last = 0;
  var m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) runs.push(bt(text.slice(last, m.index)));
    runs.push(supRef("[" + m[1] + "]"));
    last = re.lastIndex;
  }
  if (last < text.length) runs.push(bt(text.slice(last)));
  return runs.length ? runs : [bt(text)];
}

// Read humanized markdown
var md = fs.readFileSync(path.join(BASE, "\u7533\u62A5\u4E66_\u63D0\u4EA4\u7248_humanized.md"), "utf8");
var mdLines = md.split("\n");
var children = [];
var idx = 0;

while (idx < mdLines.length) {
  var ln = mdLines[idx];

  if (ln.trim() === "") { idx++; continue; }

  // Skip title (already added)
  if (/^# /.test(ln)) { idx++; continue; }

  // H1
  if (/^## /.test(ln)) {
    children.push(h1(ln.replace(/^## /, "").trim()));
    idx++; continue;
  }

  // H2
  if (/^### /.test(ln)) {
    children.push(h2(ln.replace(/^### /, "").trim()));
    idx++; continue;
  }

  // Image
  if (/^!\[/.test(ln)) {
    var im = ln.match(/^!\[(.*?)\]\((.*?)\)$/);
    if (im) {
      var alt = im[1], fn = im[2];
      var d, w, h;
      if (fn === "arch_diagram.png") { d=archImg; w=ARCH_DISP_W; h=ARCH_DISP_H; }
      else if (fn === "hardware_photo.png") { d=hwImg; w=HW_DISP_W; h=HW_DISP_H; }
      else if (fn === "techflow_diagram.png") { d=techImg; w=TECH_DISP_W; h=TECH_DISP_H; }
      if (d) {
        children.push(imgPara(d, w, h, alt));
        children.push(caption(alt));
      }
    }
    idx++; continue;
  }

  // Table
  if (/^\|/.test(ln)) {
    var tLines = [];
    while (idx < mdLines.length && /^\|/.test(mdLines[idx])) {
      tLines.push(mdLines[idx]); idx++;
    }
    if (tLines.length >= 2) {
      var th = tLines[0].split("|").filter(function(c){return c.trim();}).map(function(c){return c.trim();});
      var tr = [];
      for (var ti = 2; ti < tLines.length; ti++) {
        tr.push(tLines[ti].split("|").filter(function(c){return c.trim();}).map(function(c){return c.trim();}));
      }
      var nc = th.length;
      var cw = [];
      var tw = CONTENT_W;
      for (var ci = 0; ci < nc; ci++) {
        var cwi = Math.round(tw / nc);
        if (ci === nc - 1) cwi = tw - cw.reduce(function(a,b){return a+b},0);
        cw.push(cwi);
      }
      children.push(mkTable(th, tr, cw));
    }
    continue;
  }

  // Screenshot placeholders (lines starting with 【)
  if (/^\u3010/.test(ln)) {
    children.push(placeholder(ln.trim()));
    idx++; continue;
  }

  // Regular paragraph - collect continuation lines
  var paraText = ln.trim();
  idx++;
  while (idx < mdLines.length) {
    var next = mdLines[idx];
    if (next.trim() === "") break;
    if (/^## /.test(next) || /^### /.test(next) || /^!\[/.test(next) || /^\|/.test(next) || /^\u3010/.test(next)) break;
    paraText += next.trim();
    idx++;
  }
  children.push(bodyPara(parseInline(paraText)));
}

var doc = new Document({
  styles: {
    default: { document: { run: { font: FONT_SONG, size: SIZE_BODY } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: SIZE_H1, bold: true, font: FONT_HEI },
        paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: SIZE_H2, bold: true, font: FONT_HEI },
        paragraph: { spacing: { before: 280, after: 160 }, outlineLevel: 1 } },
    ],
  },
  sections: [{
    properties: {
      page: {
        size: { width: PAGE_W, height: PAGE_H },
        margin: { top: MARGIN_TOP, bottom: MARGIN_BOT, left: MARGIN_LEFT, right: MARGIN_RIGHT },
      },
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ children: [PageNumber.CURRENT], font: FONT_SONG, size: 18 })],
        })],
      }),
    },
    children: children,
  }],
});

var OUT = path.join(BASE, "\u661F\u7A7A\u4E0E\u8424\u706B_\u7533\u62A5\u4E66_\u63D0\u4EA4\u7248.docx");
Packer.toBuffer(doc).then(function(buffer) {
  fs.writeFileSync(OUT, buffer);
  console.log("OK: " + OUT + " (" + (buffer.length / 1024).toFixed(1) + " KB)");
}).catch(function(err) {
  console.error("Error:", err);
  process.exit(1);
});
