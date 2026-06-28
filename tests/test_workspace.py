import math
from tessera.core import Rect, Window, Workspace, TesseraConfig, SplitType


class TestWorkspace:
    def test_add_first_window_fills_usable_area(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        w, r = ws.get_layout()[0]
        assert w.id == "A"
        # 1920 - 2*outer_gap(16) - gap_size(8) = 1880
        assert r.width == 1880
        # 1080 - 2*outer_gap(16) - gap_size(8) = 1040
        assert r.height == 1040

    def test_second_window_splits_vertically_by_default(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        layout = ws.get_layout()
        assert len(layout) == 2
        a = next(w for w in layout if w[0].id == "A")
        b = next(w for w in layout if w[0].id == "B")
        # A left, B right (new window goes to right/bottom)
        assert a[1].x < b[1].x

    def test_third_window_splits_horizontal_on_focused(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.add_window(Window("C"))
        layout = ws.get_layout()
        assert len(layout) == 3
        a = next(w for w in layout if w[0].id == "A")
        c = next(w for w in layout if w[0].id == "C")
        # A and C stacked vertically (horizontal split on focused A)
        assert a[1].y < c[1].y
        # B should be to the right of A (unchanged from first split)
        b = next(w for w in layout if w[0].id == "B")
        assert b[1].x > a[1].x

    def test_focus_stays_on_existing_window(self):
        ws = Workspace(
            Rect(0, 0, 1920, 1080), TesseraConfig(new_window_focus=False)
        )
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        focused = ws._find_focused_leaf(ws.root)
        assert focused.window.id == "A"

    def test_new_window_can_get_focus(self):
        ws = Workspace(
            Rect(0, 0, 1920, 1080), TesseraConfig(new_window_focus=True)
        )
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        focused = ws._find_focused_leaf(ws.root)
        assert focused.window.id == "B"

    def test_remove_window_collapses_tree(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        removed = ws.remove_window("B")
        assert removed is not None
        assert removed.id == "B"
        assert len(ws.get_layout()) == 1
        assert ws.get_layout()[0][0].id == "A"

    def test_remove_focused_window_collapses_and_refocuses(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.focus_window("B")
        removed = ws.remove_window("B")
        assert removed is not None
        # After collapse, focus transfers to surviving window
        focused = ws._find_focused_leaf(ws.root)
        assert focused.window.id == "A"

    def test_focus_window_by_id(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.focus_window("B")
        focused = ws._find_focused_leaf(ws.root)
        assert focused.window.id == "B"

    def test_focus_nonexistent_window_returns_false(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        result = ws.focus_window("NONEXISTENT")
        assert result is False

    def test_alternating_split_direction(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))  # VERTICAL
        ws.add_window(Window("C"))  # HORIZONTAL (alternate)
        ws.add_window(Window("D"))  # VERTICAL (alternate again)
        assert len(ws.get_layout()) == 4
        # All windows should be present
        ids = {w[0].id for w in ws.get_layout()}
        assert ids == {"A", "B", "C", "D"}

    def test_gaps_inset_from_monitor_edges(self):
        outer = 32
        ws = Workspace(
            Rect(0, 0, 1920, 1080), TesseraConfig(gap_size=0, outer_gap=outer)
        )
        ws.add_window(Window("A"))
        w, r = ws.get_layout()[0]
        assert r.x == outer
        assert r.y == outer
        assert r.width == 1920 - 2 * outer
        assert r.height == 1080 - 2 * outer

    def test_zero_gaps_no_inset(self):
        ws = Workspace(Rect(0, 0, 1920, 1080), TesseraConfig(gap_size=0, outer_gap=0))
        ws.add_window(Window("A"))
        w, r = ws.get_layout()[0]
        assert r.x == 0
        assert r.y == 0
        assert r.width == 1920
        assert r.height == 1080

    def test_no_windows_returns_empty_layout(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        assert ws.get_layout() == []

    def test_remove_last_window_empties_workspace(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.remove_window("A")
        assert ws.root is None
        assert ws.get_layout() == []

    def test_remove_from_empty_workspace_returns_none(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        assert ws.remove_window("NONEXISTENT") is None

    def test_remove_already_removed_window_returns_none(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.remove_window("B")
        assert ws.remove_window("B") is None

    def test_add_after_remove_all_starts_fresh_fullscreen(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.remove_window("A")
        ws.remove_window("B")
        ws.add_window(Window("C"))
        w, r = ws.get_layout()[0]
        assert w.id == "C"
        assert r.width == 1880
        assert r.height == 1040
        assert ws.root is not None and ws.root.is_leaf

    def test_focus_same_window_twice_returns_true(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        assert ws.focus_window("A") is True
        assert ws.focus_window("A") is True
        focused = ws._find_focused_leaf(ws.root)
        assert focused.window.id == "A"

    def test_focus_on_empty_workspace_returns_false(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        assert ws.focus_window("A") is False

    def test_deeply_nested_tree_seven_windows(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        for i in range(7):
            ws.add_window(Window(chr(65 + i)))
        layout = ws.get_layout()
        assert len(layout) == 7
        ids = {w[0].id for w in layout}
        assert ids == {"A", "B", "C", "D", "E", "F", "G"}
        # All rects should be within monitor bounds
        for w, r in layout:
            assert r.x >= 0
            assert r.y >= 0
            assert r.x + r.width <= 1920
            assert r.y + r.height <= 1080

    def test_add_remove_cycle_preserves_correctness(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.remove_window("B")
        ws.add_window(Window("C"))
        ws.remove_window("A")
        ws.add_window(Window("D"))
        layout = ws.get_layout()
        assert len(layout) == 2
        ids = {w[0].id for w in layout}
        assert ids == {"C", "D"}

    def test_remove_middle_window_from_three(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.add_window(Window("C"))
        ws.remove_window("B")
        layout = ws.get_layout()
        assert len(layout) == 2
        ids = {w[0].id for w in layout}
        assert ids == {"A", "C"}

    def test_total_area_invariant_no_gaps(self):
        ws = Workspace(Rect(0, 0, 1920, 1080), TesseraConfig(gap_size=0, outer_gap=0))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.add_window(Window("C"))
        layout = ws.get_layout()
        total_visible_area = sum(r.width * r.height for _, r in layout)
        assert math.isclose(total_visible_area, 1920 * 1080)

    def test_empty_string_window_id(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window(""))
        w, r = ws.get_layout()[0]
        assert w.id == ""
        ws.add_window(Window("B"))
        assert len(ws.get_layout()) == 2

    def test_large_monitor_rect(self):
        ws = Workspace(Rect(0, 0, 7680, 4320), TesseraConfig(gap_size=16, outer_gap=32))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.add_window(Window("C"))
        layout = ws.get_layout()
        assert len(layout) == 3
        for _, r in layout:
            assert r.width > 0 and r.height > 0

    def test_focus_after_remove_add_cycle(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))
        ws.focus_window("B")
        ws.remove_window("B")
        ws.add_window(Window("C"))
        focused = ws._find_focused_leaf(ws.root)
        assert focused.window.id == "A"

    def test_split_alternates_correctly_after_remove_add_cycle(self):
        ws = Workspace(Rect(0, 0, 1920, 1080))
        ws.add_window(Window("A"))
        ws.add_window(Window("B"))  # V
        ws.remove_window("B")
        ws.add_window(Window("C"))  # H (continues alternating from V)
        # After B: _next_split = H. Add C uses H → splits A top/bottom. Then alternates to V.
        layout = ws.get_layout()
        assert len(layout) == 2
        ids = {w[0].id for w in layout}
        assert ids == {"A", "C"}
        # A should be above C (horizontal split)
        a = next(w for w in layout if w[0].id == "A")
        c = next(w for w in layout if w[0].id == "C")
        assert a[1].y < c[1].y
        assert ws._next_split == SplitType.VERTICAL
