from typing import Optional
from .models import Rect, Window, SplitType
from .config import TesseraConfig


class TreeNode:
    def __init__(
        self,
        rect: Rect,
        window: Optional[Window] = None,
        left_child: Optional["TreeNode"] = None,
        right_child: Optional["TreeNode"] = None,
        split_type: Optional[SplitType] = None,
        is_focused: bool = False,
    ):
        self.rect = rect
        self.window = window
        self.left_child = left_child
        self.right_child = right_child
        self.split_type = split_type
        self.is_focused = is_focused

    @property
    def is_leaf(self) -> bool:
        return self.left_child is None and self.right_child is None

    def __repr__(self) -> str:
        if self.is_leaf:
            return f"Leaf(window={self.window}, rect={self.rect}, focused={self.is_focused})"
        dir_label = "H" if self.split_type == SplitType.HORIZONTAL else "V"
        return f"Node({dir_label}, left={self.left_child}, right={self.right_child})"


class Workspace:
    def __init__(self, monitor_rect: Rect, config: Optional[TesseraConfig] = None):
        self.monitor_rect = monitor_rect
        self.config = config or TesseraConfig()
        self.root: Optional[TreeNode] = None
        self._next_split = self.config.initial_split

    def add_window(self, window: Window) -> None:
        gap = self.config.gap_size / 2.0

        if self.root is None:
            usable = self.monitor_rect.inset(self.config.outer_gap)
            window.rect = usable.inset(gap)
            self.root = TreeNode(rect=usable, window=window, is_focused=True)
            return

        focused = self._find_focused_leaf(self.root)

        old_window = focused.window
        old_rect = focused.rect

        if self._next_split == SplitType.VERTICAL:
            left_rect, right_rect = old_rect.split_vertical()
            existing_rect = left_rect
            new_rect = right_rect
        else:
            top_rect, bottom_rect = old_rect.split_horizontal()
            existing_rect = top_rect
            new_rect = bottom_rect

        existing_window = old_window
        existing_window.rect = existing_rect.inset(gap)
        new_window = window
        new_window.rect = new_rect.inset(gap)

        focused.window = None
        focused.split_type = self._next_split
        focused.left_child = TreeNode(rect=existing_rect, window=existing_window, is_focused=not self.config.new_window_focus)
        focused.right_child = TreeNode(rect=new_rect, window=new_window, is_focused=self.config.new_window_focus)

        self._next_split = self._next_split.alternate()

    def remove_window(self, window_id: str) -> Optional[Window]:
        if self.root is None:
            return None

        path = self._find_path_to_leaf(self.root, window_id)
        if path is None:
            return None

        target_node, parent = path
        removed = target_node.window

        if parent is None:
            self.root = None
            self._next_split = self.config.initial_split
            return removed

        if parent.left_child is target_node:
            surviving = parent.right_child
        else:
            surviving = parent.left_child

        parent.window = surviving.window
        parent.rect = surviving.rect
        parent.left_child = surviving.left_child
        parent.right_child = surviving.right_child
        parent.split_type = surviving.split_type
        parent.is_focused = True

        return removed

    def focus_window(self, window_id: str) -> bool:
        self._clear_focus(self.root)
        return self._set_focus_by_id(self.root, window_id)

    def _clear_focus(self, node: Optional[TreeNode]) -> None:
        if node is None:
            return
        node.is_focused = False
        self._clear_focus(node.left_child)
        self._clear_focus(node.right_child)

    def get_layout(self) -> list[tuple[Window, Rect]]:
        result: list[tuple[Window, Rect]] = []
        self._collect_leaves(self.root, result)
        return result

    def _find_focused_leaf(self, node: TreeNode) -> TreeNode:
        if node.is_leaf:
            return node
        candidate = self._find_focused_leaf(node.left_child)
        if candidate.is_focused:
            return candidate
        return self._find_focused_leaf(node.right_child)

    def _find_path_to_leaf(
        self, node: Optional[TreeNode], window_id: str, parent: Optional[TreeNode] = None
    ) -> Optional[tuple[TreeNode, Optional[TreeNode]]]:
        if node is None:
            return None
        if node.is_leaf:
            if node.window and node.window.id == window_id:
                return (node, parent)
            return None
        left_result = self._find_path_to_leaf(node.left_child, window_id, node)
        if left_result is not None:
            return left_result
        return self._find_path_to_leaf(node.right_child, window_id, node)

    def _set_focus_by_id(self, node: Optional[TreeNode], window_id: str) -> bool:
        if node is None:
            return False
        if node.is_leaf:
            if node.window and node.window.id == window_id:
                node.is_focused = True
                return True
            return False
        found_left = self._set_focus_by_id(node.left_child, window_id)
        if found_left:
            return True
        return self._set_focus_by_id(node.right_child, window_id)

    def _collect_leaves(
        self, node: Optional[TreeNode], result: list[tuple[Window, Rect]]
    ) -> None:
        if node is None:
            return
        if node.is_leaf and node.window is not None:
            result.append((node.window, node.window.rect))
            return
        self._collect_leaves(node.left_child, result)
        self._collect_leaves(node.right_child, result)
