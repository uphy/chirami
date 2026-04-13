import { EditorView, ViewPlugin, ViewUpdate, keymap } from "@codemirror/view";
import { Prec } from "@codemirror/state";
import { openTldrawOverlay } from "../tldraw-overlay";

export interface SlashCommand {
  id: string;
  label: string;
  description: string;
  execute(view: EditorView, lineFrom: number): void;
}

const COMMANDS: SlashCommand[] = [
  {
    id: "tldraw",
    label: "/tldraw",
    description: "Insert a tldraw diagram block",
    execute(view, lineFrom) {
      const block = "```tldraw\n\n```";
      const lineTo = view.state.doc.lineAt(lineFrom).to;
      view.dispatch({
        changes: { from: lineFrom, to: lineTo, insert: block },
        selection: { anchor: lineFrom + block.length },
      });
      const codeFrom = lineFrom + "```tldraw\n".length;
      openTldrawOverlay("", (newSnapshot) => {
        if (!newSnapshot) return;
        view.dispatch({
          changes: { from: codeFrom, to: codeFrom, insert: newSnapshot + "\n" },
        });
      });
    },
  },
  {
    id: "mermaid",
    label: "/mermaid",
    description: "Insert a mermaid diagram block",
    execute(view, lineFrom) {
      const initialContent = "graph TD\n    A --> B";
      const block = "```mermaid\n" + initialContent + "\n```";
      const cursorPos = lineFrom + "```mermaid\n".length + initialContent.length;
      view.dispatch({
        changes: { from: lineFrom, to: view.state.doc.lineAt(lineFrom).to, insert: block },
        selection: { anchor: cursorPos },
      });
    },
  },
  {
    id: "table",
    label: "/table",
    description: "Insert a Markdown table template",
    execute(view, lineFrom) {
      const template = "| | |\n|---|---|\n| | |";
      const cursorPos = lineFrom + "| ".length;
      view.dispatch({
        changes: { from: lineFrom, to: view.state.doc.lineAt(lineFrom).to, insert: template },
        selection: { anchor: cursorPos },
      });
    },
  },
];

function buildPickerDOM(
  commands: SlashCommand[],
  selectedIndex: number,
  onSelect: (index: number) => void
): HTMLUListElement {
  const ul = document.createElement("ul");
  ul.className = "cm-slash-picker";

  commands.forEach((cmd, i) => {
    const li = document.createElement("li");
    li.className = "cm-slash-picker-item" + (i === selectedIndex ? " cm-slash-picker-item--selected" : "");

    const label = document.createElement("span");
    label.className = "cm-slash-picker-label";
    label.textContent = cmd.label;

    const desc = document.createElement("span");
    desc.className = "cm-slash-picker-desc";
    desc.textContent = cmd.description;

    li.appendChild(label);
    li.appendChild(desc);
    li.addEventListener("mousedown", (e) => {
      e.preventDefault();
      onSelect(i);
    });
    ul.appendChild(li);
  });

  return ul;
}

class SlashCommandPicker {
  private el: HTMLUListElement | null = null;
  private selectedIndex = 0;
  private filteredCommands: SlashCommand[] = [];
  private slashLineFrom = -1;
  private rafId: number | null = null;

  get isOpen(): boolean {
    return this.el !== null;
  }

  open(view: EditorView, lineFrom: number, filter: string): void {
    this.slashLineFrom = lineFrom;
    this.selectedIndex = 0;
    this.filteredCommands = this.filterCommands(filter);

    if (this.filteredCommands.length === 0) {
      this.close();
      return;
    }

    this.render(view);
  }

  updateFilter(view: EditorView, filter: string): void {
    if (!this.isOpen) return;

    this.filteredCommands = this.filterCommands(filter);

    if (this.filteredCommands.length === 0) {
      this.close();
      return;
    }

    if (this.selectedIndex >= this.filteredCommands.length) {
      this.selectedIndex = this.filteredCommands.length - 1;
    }

    this.render(view);
  }

  moveSelection(delta: number): void {
    if (!this.isOpen || this.filteredCommands.length === 0) return;
    this.selectedIndex = (this.selectedIndex + delta + this.filteredCommands.length) % this.filteredCommands.length;
    this.refreshHighlight();
  }

  confirmSelection(view: EditorView): void {
    if (!this.isOpen || this.filteredCommands.length === 0) return;
    const cmd = this.filteredCommands[this.selectedIndex];
    const lineFrom = this.slashLineFrom;
    this.close();
    cmd.execute(view, lineFrom);
  }

  close(): void {
    this.removeDOM();
    this.slashLineFrom = -1;
  }

  private render(view: EditorView): void {
    this.removeDOM();
    this.el = buildPickerDOM(this.filteredCommands, this.selectedIndex, (i) => {
      this.selectedIndex = i;
      this.confirmSelection(view);
    });
    document.body.appendChild(this.el);
    this.position(view);
  }

  private removeDOM(): void {
    if (this.el && this.el.parentNode) {
      this.el.parentNode.removeChild(this.el);
    }
    this.el = null;
  }

  private filterCommands(filter: string): SlashCommand[] {
    if (!filter) return COMMANDS;
    const q = filter.toLowerCase();
    return COMMANDS.filter((c) => c.id.startsWith(q) || c.label.toLowerCase().startsWith("/" + q));
  }

  private refreshHighlight(): void {
    if (!this.el) return;
    const items = this.el.querySelectorAll(".cm-slash-picker-item");
    items.forEach((item, i) => {
      item.classList.toggle("cm-slash-picker-item--selected", i === this.selectedIndex);
    });
  }

  // Uses requestAnimationFrame so coordsAtPos runs after CodeMirror finishes re-rendering.
  // Cancels any pending frame before scheduling a new one to avoid stale-closure positioning.
  private position(view: EditorView): void {
    if (!this.el) return;
    this.el.style.position = "fixed";

    if (this.rafId !== null) cancelAnimationFrame(this.rafId);
    this.rafId = requestAnimationFrame(() => {
      this.rafId = null;
      if (!this.el) return;

      const head = view.state.selection.main.head;
      let coords = view.coordsAtPos(head);
      if (!coords) {
        const line = view.state.doc.lineAt(head);
        coords = view.coordsAtPos(line.from);
      }

      const PICKER_HEIGHT = 200;
      const MARGIN = 4;
      const viewportHeight = window.innerHeight;

      if (!coords) {
        const editorRect = view.dom.getBoundingClientRect();
        this.el.style.left = `${editorRect.left + 16}px`;
        this.el.style.top = `${editorRect.top + 40}px`;
        return;
      }

      this.el.style.left = `${coords.left}px`;

      if (coords.bottom + PICKER_HEIGHT + MARGIN > viewportHeight) {
        this.el.style.top = "";
        this.el.style.bottom = `${viewportHeight - coords.top + MARGIN}px`;
      } else {
        this.el.style.top = `${coords.bottom + MARGIN}px`;
        this.el.style.bottom = "";
      }
    });
  }
}

const picker = new SlashCommandPicker();

class SlashCommandPlugin {
  constructor(_view: EditorView) {}

  update(update: ViewUpdate): void {
    if (!update.docChanged && !update.selectionSet) return;
    if (!update.docChanged && !picker.isOpen) return;

    const view = update.view;
    const state = view.state;
    const head = state.selection.main.head;
    const line = state.doc.lineAt(head);
    const lineText = state.sliceDoc(line.from, head);

    if (/^\/[a-zA-Z]*$/.test(lineText)) {
      const filter = lineText.slice(1);
      if (picker.isOpen) {
        picker.updateFilter(view, filter);
      } else {
        picker.open(view, line.from, filter);
      }
    } else if (picker.isOpen) {
      picker.close();
    }
  }

  destroy(): void {
    picker.close();
  }
}

const slashCommandPlugin = ViewPlugin.fromClass(SlashCommandPlugin);

const slashKeymap = keymap.of([
  {
    key: "ArrowUp",
    run(): boolean {
      if (!picker.isOpen) return false;
      picker.moveSelection(-1);
      return true;
    },
  },
  {
    key: "ArrowDown",
    run(): boolean {
      if (!picker.isOpen) return false;
      picker.moveSelection(1);
      return true;
    },
  },
  {
    key: "Enter",
    run(view: EditorView): boolean {
      if (!picker.isOpen) return false;
      picker.confirmSelection(view);
      return true;
    },
  },
  {
    key: "Escape",
    run(): boolean {
      if (!picker.isOpen) return false;
      picker.close();
      return true;
    },
  },
]);

export const slashCommandExtension = [slashCommandPlugin, Prec.high(slashKeymap)];
