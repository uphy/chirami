import { describe, expect, it } from "vitest";
import { htmlToMarkdown } from "./smartPaste";

describe("htmlToMarkdown", () => {
  it("indents nested bullets with tabs and uses '- ' markers", () => {
    const html = "<ul><li>a<ul><li>b<ul><li>c</li></ul></li></ul></li><li>d</li></ul>";
    expect(htmlToMarkdown(html)).toBe("- a\n\t- b\n\t\t- c\n- d");
  });

  it("uses 'N. ' markers for ordered lists and honors the start attribute", () => {
    const html = '<ol start="3"><li>three</li><li>four</li></ol>';
    expect(htmlToMarkdown(html)).toBe("3. three\n4. four");
  });

  it("indents a list nested under an ordered item with a tab", () => {
    const html = "<ol><li>one<ul><li>sub</li></ul></li></ol>";
    expect(htmlToMarkdown(html)).toBe("1. one\n\t- sub");
  });

  it("keeps task list checkboxes", () => {
    const html =
      '<ul><li><input type="checkbox" checked>done</li><li><input type="checkbox">todo</li></ul>';
    expect(htmlToMarkdown(html)).toBe("- [x] done\n- [ ] todo");
  });

  it("indents multi-paragraph list item content with tabs", () => {
    const html = "<ul><li><p>first</p><p>second</p></li></ul>";
    expect(htmlToMarkdown(html)).toBe("- first\n\t\n\tsecond");
  });

  it("leaves space indentation inside code blocks untouched", () => {
    const html = "<ul><li>item<pre><code>def f():\n    return 1</code></pre></li></ul>";
    expect(htmlToMarkdown(html)).toBe("- item\n\t\n\t```\n\tdef f():\n\t    return 1\n\t```");
  });

  it("does not indent headings or paragraphs outside lists", () => {
    const html = "<h1>Title</h1><p>body</p>";
    expect(htmlToMarkdown(html)).toBe("# Title\n\nbody");
  });
});
