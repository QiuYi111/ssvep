export class MarkdownRenderer {
  static render(markdown: string): string {
    let html = markdown;

    // Remove first H1 (handled by hero)
    html = html.replace(/^# .*\n/, '');

    // Headers (## Title) -> <section class="about-section"><h2>Title</h2>
    let sectionCount = 0;
    html = html.replace(/## (.*)/g, (_, title) => {
      sectionCount++;
      return `</section><section class="about-section"><h2>${sectionCount}. ${title}</h2>`;
    });

    // Horizontal Rules
    html = html.replace(/---/g, '<div class="about-divider"></div>');

    // Links [text](url)
    html = html.replace(/\[(.*?)\]\((.*?)\)/g, '<a href="$2" target="_blank" class="about-link">$1</a>');

    // Paragraphs (split by double newline)
    const lines = html.split('\n\n');
    html = lines.map(line => {
      if (line.trim().startsWith('<section') || line.trim().startsWith('</section') || line.trim().startsWith('<div')) {
        return line;
      }
      return `<p>${line.trim()}</p>`;
    }).join('');

    // Wrap the whole thing in a starting section if needed
    if (!html.trim().startsWith('<section')) {
      html = '<section class="about-section">' + html;
    }
    if (!html.trim().endsWith('</section>')) {
      html += '</section>';
    }

    return html;
  }
}
