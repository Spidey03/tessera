from tessera.core.models import Rect, Window, SplitType
from tessera.core.config import TesseraConfig
from tessera.core.workspace import Workspace


def print_layout(ws: Workspace, title: str = ""):
    if title:
        print(f"\n{'=' * 60}")
        print(f"  {title}")
        print(f"{'=' * 60}")
    print(f"{'Window':<10} {'X':>6} {'Y':>6} {'W':>6} {'H':>6} {'Focused':>8}")
    print("-" * 50)
    for window, rect in ws.get_layout():
        focused_mark = "  <-" if ws._find_focused_leaf(ws.root).window == window else ""
        print(f"{window.id:<10} {rect.x:>6.0f} {rect.y:>6.0f} {rect.width:>6.0f} {rect.height:>6.0f}  {focused_mark}")
    print()


def main():
    monitor = Rect(0, 0, 1920, 1080)

    config = TesseraConfig(
        gap_size=8,
        outer_gap=16,
        initial_split=SplitType.VERTICAL,
        new_window_focus=False,
    )

    ws = Workspace(monitor, config)

    print("Monitor: 1920x1080")
    print(f"Config: gap_size={config.gap_size}, outer_gap={config.outer_gap}")
    print(f"Initial split: {config.initial_split.value}, New window focus: {config.new_window_focus}")

    ws.add_window(Window("A"))
    print_layout(ws, "After adding Window A")

    ws.add_window(Window("B"))
    print_layout(ws, "After adding Window B (vertical split on A)")

    ws.add_window(Window("C"))
    print_layout(ws, "After adding Window C (horizontal split on A)")

    print("\nDetailed tree structure:")
    _print_tree(ws.root, 0)


def _print_tree(node, depth: int):
    indent = "  " * depth
    if node.is_leaf:
        w_id = node.window.id if node.window else "None"
        f = " (focused)" if node.is_focused else ""
        print(f"{indent}Leaf[{w_id}]{f} {node.rect}")
    else:
        dir_label = "H" if node.split_type == SplitType.HORIZONTAL else "V"
        print(f"{indent}Internal[{dir_label}]")
        _print_tree(node.left_child, depth + 1)
        _print_tree(node.right_child, depth + 1)


if __name__ == "__main__":
    main()
