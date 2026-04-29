type ActionResult = { output: string; is_error: boolean };

const INTERACTIVE_ROLES = new Set([
  "button", "link", "textbox", "searchbox", "combobox", "listbox", "option",
  "checkbox", "radio", "switch", "slider", "spinbutton", "menuitem", "menuitemcheckbox",
  "menuitemradio", "tab", "treeitem", "gridcell", "columnheader", "rowheader",
  "scrollbar", "separator", "toolbar", "tooltip",
]);

const INTERACTIVE_TAGS = new Set([
  "a", "button", "input", "select", "textarea", "details", "summary",
]);

const LANDMARK_ROLES = new Set([
  "main", "nav", "banner", "contentinfo", "complementary", "search",
  "form", "region", "article", "section",
]);

const HEADING_ROLES = new Set(["heading"]);

let refCounter = 0;

function getAriaRole(el: Element): string {
  const explicit = el.getAttribute("role");
  if (explicit) return explicit;

  const tag = el.tagName.toLowerCase();
  const type = (el as HTMLInputElement).type?.toLowerCase();

  switch (tag) {
    case "a": return (el as HTMLAnchorElement).href ? "link" : "generic";
    case "button": return "button";
    case "input":
      if (type === "checkbox") return "checkbox";
      if (type === "radio") return "radio";
      if (type === "range") return "slider";
      if (type === "submit" || type === "button" || type === "reset") return "button";
      return "textbox";
    case "select": return "listbox";
    case "textarea": return "textbox";
    case "nav": return "nav";
    case "main": return "main";
    case "header": return "banner";
    case "footer": return "contentinfo";
    case "aside": return "complementary";
    case "form": return "form";
    case "section": return "region";
    case "article": return "article";
    case "h1": case "h2": case "h3": case "h4": case "h5": case "h6": return "heading";
    default: return tag;
  }
}

function getAccessibleName(el: Element): string {
  const labelledBy = el.getAttribute("aria-labelledby");
  if (labelledBy) {
    const names = labelledBy.split(/\s+/).map((id) => {
      const ref = document.getElementById(id);
      return ref ? ref.textContent?.trim() ?? "" : "";
    });
    const joined = names.join(" ").trim();
    if (joined) return joined;
  }

  const label = el.getAttribute("aria-label");
  if (label?.trim()) return label.trim();

  const title = el.getAttribute("title");
  if (title?.trim()) return title.trim();

  const placeholder = (el as HTMLInputElement).placeholder;
  if (placeholder?.trim()) return placeholder.trim();

  const alt = (el as HTMLImageElement).alt;
  if (alt?.trim()) return alt.trim();

  const text = el.textContent?.trim().slice(0, 80) ?? "";
  return text;
}

function getElementValue(el: Element): string | null {
  const tag = el.tagName.toLowerCase();
  if (tag === "input" || tag === "textarea") {
    return (el as HTMLInputElement).value;
  }
  if (tag === "select") {
    const sel = el as HTMLSelectElement;
    return sel.options[sel.selectedIndex]?.text ?? "";
  }
  const ariaVal = el.getAttribute("aria-valuenow");
  if (ariaVal) return ariaVal;
  return null;
}

function isHidden(el: Element): boolean {
  if (el.getAttribute("aria-hidden") === "true") return true;
  if ((el as HTMLElement).hidden) return true;
  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return true;
  return false;
}

function shouldInclude(el: Element, mode: "interactive" | "full"): boolean {
  if (isHidden(el)) return false;
  const role = getAriaRole(el);
  const tag = el.tagName.toLowerCase();

  if (INTERACTIVE_ROLES.has(role) || INTERACTIVE_TAGS.has(tag)) return true;
  if (mode === "full" && (LANDMARK_ROLES.has(role) || HEADING_ROLES.has(role))) return true;
  return false;
}

function assignRef(el: Element): number {
  const existing = el.getAttribute("data-viber-ref");
  if (existing) return parseInt(existing, 10);
  const ref = ++refCounter;
  el.setAttribute("data-viber-ref", String(ref));
  return ref;
}

function buildNodeLine(el: Element, depth: number): string {
  const ref = assignRef(el);
  const role = getAriaRole(el);
  const name = getAccessibleName(el);
  const value = getElementValue(el);
  const disabled = (el as HTMLButtonElement).disabled || el.getAttribute("aria-disabled") === "true";
  const checked = el.getAttribute("aria-checked") ?? (el as HTMLInputElement).checked?.toString() ?? null;
  const expanded = el.getAttribute("aria-expanded");
  const level = el.getAttribute("aria-level") ?? el.tagName.match(/^H([1-6])$/i)?.[1];

  const indent = "  ".repeat(depth);
  let line = `${indent}[${ref}] ${role}`;
  if (name) line += ` "${name}"`;
  if (value !== null && value !== "") line += ` value="${value}"`;
  if (level) line += ` level=${level}`;
  if (expanded !== null) line += ` expanded=${expanded}`;
  if (disabled) line += " disabled";
  if (checked !== null && checked !== "false") line += ` checked=${checked}`;
  if (role === "link") {
    const href = (el as HTMLAnchorElement).href;
    if (href) line += ` (href="${href.slice(0, 60)}")`;
  }

  return line;
}

function walkTree(
  root: Element,
  mode: "interactive" | "full",
  depth: number,
  lines: string[]
): void {
  for (const child of Array.from(root.children)) {
    if (shouldInclude(child, mode)) {
      lines.push(buildNodeLine(child, depth));
      walkTree(child, mode, depth + 1, lines);
    } else {
      walkTree(child, mode, depth, lines);
    }
  }
}

function buildA11yTree(mode: "interactive" | "full" = "interactive"): string {
  refCounter = 0;
  document.querySelectorAll("[data-viber-ref]").forEach((el) => {
    el.removeAttribute("data-viber-ref");
  });

  const lines: string[] = [];
  walkTree(document.body, mode, 0, lines);
  return lines.join("\n");
}

function resolveRef(ref: number): Element | null {
  return document.querySelector(`[data-viber-ref="${ref}"]`);
}

async function executeAction(
  toolName: string,
  input: Record<string, unknown>
): Promise<ActionResult> {
  try {
    switch (toolName) {
      case "browser_click": {
        const el = resolveRef(input.ref as number);
        if (!el) return { output: `Element [${input.ref}] not found`, is_error: true };
        (el as HTMLElement).focus();
        (el as HTMLElement).click();
        return { output: `Clicked element [${input.ref}]`, is_error: false };
      }

      case "browser_type": {
        const el = resolveRef(input.ref as number) as HTMLInputElement | null;
        if (!el) return { output: `Element [${input.ref}] not found`, is_error: true };
        el.focus();
        const text = input.text as string;

        if ("value" in el) {
          const nativeInputDescriptor = Object.getOwnPropertyDescriptor(
            Object.getPrototypeOf(el),
            "value"
          );
          nativeInputDescriptor?.set?.call(el, text);
          el.dispatchEvent(new Event("input", { bubbles: true }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        } else if ((el as HTMLElement).contentEditable === "true") {
          (el as HTMLElement).textContent = text;
          (el as HTMLElement).dispatchEvent(new Event("input", { bubbles: true }));
        }

        return { output: `Typed into element [${input.ref}]`, is_error: false };
      }

      case "browser_scroll": {
        const direction = input.direction as string;
        const amount = (input.amount as number | undefined) ?? 300;
        const ref = input.ref as number | undefined;

        if (ref !== undefined) {
          const el = resolveRef(ref);
          if (!el) return { output: `Element [${ref}] not found`, is_error: true };
          el.scrollIntoView({ behavior: "smooth", block: "center" });
          return { output: `Scrolled element [${ref}] into view`, is_error: false };
        }

        const x = direction === "left" ? -amount : direction === "right" ? amount : 0;
        const y = direction === "up" ? -amount : direction === "down" ? amount : 0;
        window.scrollBy({ left: x, top: y, behavior: "smooth" });
        return { output: `Scrolled ${direction} by ${amount}px`, is_error: false };
      }

      case "browser_navigate": {
        const url = input.url as string;
        const scheme = url.split(":")[0].toLowerCase();
        if (scheme !== "http" && scheme !== "https") {
          return { output: `Blocked navigation to unsafe URL scheme: ${scheme}`, is_error: true };
        }
        window.location.href = url;
        return { output: `Navigating to ${url}`, is_error: false };
      }

      case "browser_focus": {
        const el = resolveRef(input.ref as number) as HTMLElement | null;
        if (!el) return { output: `Element [${input.ref}] not found`, is_error: true };
        el.focus();
        return { output: `Focused element [${input.ref}]`, is_error: false };
      }

      case "browser_get_accessibility_tree": {
        const mode = (input.mode as "interactive" | "full" | undefined) ?? "interactive";
        const tree = buildA11yTree(mode);
        return { output: tree, is_error: false };
      }

      default:
        return { output: `Unknown browser tool: ${toolName}`, is_error: true };
    }
  } catch (e) {
    return { output: `Error executing ${toolName}: ${String(e)}`, is_error: true };
  }
}

export default defineContentScript({
  matches: ["<all_urls>"],
  runAt: "document_idle",
  main() {
    (window as Window & {
      __viber_build_a11y_tree?: (mode?: "interactive" | "full") => string;
      __viber_execute_action?: (toolName: string, input: Record<string, unknown>) => Promise<ActionResult>;
    }).__viber_build_a11y_tree = buildA11yTree;

    (window as Window & {
      __viber_execute_action?: (toolName: string, input: Record<string, unknown>) => Promise<ActionResult>;
    }).__viber_execute_action = executeAction;
  },
});
