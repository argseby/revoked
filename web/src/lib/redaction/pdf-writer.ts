// Writes a PDF whose every page is one JPEG. Used for a redacted PDF: the
// pages are flattened to pixels, so nothing under a black box — no text layer,
// no hidden object — survives into the file.

export interface ImagePage {
  jpeg: Uint8Array;
  pixelWidth: number;
  pixelHeight: number;
  // Page size in PDF points (1/72 inch), as the original page was.
  width: number;
  height: number;
}

const enc = new TextEncoder();

export function buildPdf(pages: ImagePage[]): Uint8Array {
  const chunks: Uint8Array[] = [];
  const offsets: number[] = [];
  let length = 0;
  const push = (b: Uint8Array) => {
    chunks.push(b);
    length += b.length;
  };
  const text = (s: string) => push(enc.encode(s));
  const object = (id: number, body: () => void) => {
    offsets[id] = length;
    text(`${id} 0 obj\n`);
    body();
    text('\nendobj\n');
  };

  // Objects: 1 catalog, 2 page tree, then per page: page, contents, image.
  const pageId = (i: number) => 3 + i * 3;
  const count = 3 + pages.length * 3;

  text('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  object(1, () => text('<< /Type /Catalog /Pages 2 0 R >>'));
  object(2, () =>
    text(`<< /Type /Pages /Kids [${pages.map((_, i) => `${pageId(i)} 0 R`).join(' ')}] /Count ${pages.length} >>`),
  );
  pages.forEach((p, i) => {
    const id = pageId(i);
    const w = p.width.toFixed(2);
    const h = p.height.toFixed(2);
    object(id, () =>
      text(
        `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${w} ${h}] ` +
          `/Resources << /XObject << /Im0 ${id + 2} 0 R >> >> /Contents ${id + 1} 0 R >>`,
      ),
    );
    const draw = `q ${w} 0 0 ${h} 0 0 cm /Im0 Do Q`;
    object(id + 1, () => text(`<< /Length ${draw.length} >>\nstream\n${draw}\nendstream`));
    object(id + 2, () => {
      text(
        `<< /Type /XObject /Subtype /Image /Width ${p.pixelWidth} /Height ${p.pixelHeight} ` +
          `/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n`,
      );
      push(p.jpeg);
      text('\nendstream');
    });
  });

  const xref = length;
  text(`xref\n0 ${count}\n0000000000 65535 f \n`);
  for (let id = 1; id < count; id++) text(`${String(offsets[id]).padStart(10, '0')} 00000 n \n`);
  text(`trailer\n<< /Size ${count} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`);

  const out = new Uint8Array(length);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
}
