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

describe("htmlToMarkdown underscore escaping", () => {
  it("leaves intraword underscores unescaped", () => {
    expect(htmlToMarkdown("<p>user_name calls max_count</p>")).toBe("user_name calls max_count");
  });

  it("treats a run of intraword underscores as one delimiter", () => {
    expect(htmlToMarkdown("<p>user__name</p>")).toBe("user__name");
  });

  it("counts non-ASCII letters as word characters", () => {
    expect(htmlToMarkdown("<p>見出し_本文</p>")).toBe("見出し_本文");
  });

  it("keeps the escape where the underscore could open emphasis", () => {
    expect(htmlToMarkdown("<p>_emphasis_ and __strong__</p>")).toBe(
      "\\_emphasis\\_ and \\_\\_strong\\_\\_",
    );
  });

  it("keeps the escape at a text node edge, where the neighbour is unknown", () => {
    // turndown's default emphasis delimiter is "_", hence the run that follows.
    expect(htmlToMarkdown("<p>lead_<em>tail</em></p>")).toBe("lead\\__tail_");
  });

  it("keeps the escape next to punctuation", () => {
    expect(htmlToMarkdown("<p>foo_(bar)</p>")).toBe("foo\\_(bar)");
  });

  it("still escapes a literal backslash that precedes an underscore", () => {
    expect(htmlToMarkdown("<p>a\\_b</p>")).toBe("a\\\\\\_b");
  });

  it("leaves other escapes alone", () => {
    expect(htmlToMarkdown("<p>2 * 3 [x] `code`</p>")).toBe("2 \\* 3 \\[x\\] \\`code\\`");
  });

  it("does not touch underscores inside code", () => {
    expect(htmlToMarkdown("<p><code>__init__</code></p>")).toBe("`__init__`");
  });
});
