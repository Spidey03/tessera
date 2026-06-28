# Tessera BSP layout engine prototype

**Session ID:** ses_0f37ee926ffetTlmGYRzYvW6Qh
**Created:** 6/28/2026, 10:03:34 AM
**Updated:** 6/28/2026, 10:51:59 AM

---

## User

Master Prompt: Tessera Window Manager Development

Context & Persona:
Act as an expert Systems Engineer and macOS Developer specializing in low-level operating system APIs (CoreGraphics, ApplicationServices) and window management architecture.

Project Overview:
I am building "Tessera", a custom tiling window manager and workspace manager for macOS.
Unlike native macOS Spaces, Tessera will use Virtual Workspaces to bypass Apple's slow, unskippable animations. It will maintain a single large invisible canvas and use a Binary Space Partitioning (BSP) tree to instantly calculate, hide, show, and resize windows when switching contexts or adding new applications.

Architectural Strategy (The "Brain" vs. "Body"):
Because macOS development can be tricky to test rapidly, we are decoupling the logic from the OS.

The Brain (OS-Agnostic): We will build the Layout Engine (BSP tree, vector focus math, and virtual workspace state map) in Python first for rapid prototyping.

The Body (macOS-Specific): Later, we will port this logic to Swift and wire it up to Apple's AXUIElement (Accessibility API) to manipulate actual windows, and CGEventTap to intercept global keyboard shortcuts.

Your Current Task: Phase 1 (The Python Prototype)

I want to start by building the pure mathematical "Brain" of Tessera in Python. We will not touch macOS APIs yet. We are building the data structures and the BSP layout engine.

Please guide me through completing Phase 1, addressing the following defined tasks one by one. Provide the Python code for each step:

Task 1: Core Data Models
Define the base classes: Rect (X, Y, Width, Height) and Window (ID, current Rect).

Task 2: The BSP Tree Node
Create a TreeNode class. It needs to hold a Rect, optionally hold a Window (if it's a leaf node), and have pointers to a left_child and right_child. Define constants for SplitType (Horizontal/Vertical).

Task 3: The Splitting Algorithm (The Engine)
Write the Workspace manager class. Implement the add_window(window) function.

If the workspace is empty, the new window takes the full Monitor Rect.

If it's not empty, the algorithm must find the currently focused leaf node, split its Rect exactly in half (alternating horizontal/vertical), move the existing window into one child node, and put the new window into the other child node.

Task 4: CLI Visualization
Write a simple simulation script where I can define a 1920x1080 monitor, add 3 mock windows sequentially, and print the resulting calculated X, Y, W, H coordinates for each window to the terminal to verify the math works.

Instructions for your response:
Take a deep breath and let's tackle Task 1 and Task 2 first. Show me the Python code, explain the structure, and wait for my confirmation before moving to Task 3. 

---

## Assistant (Build · DeepSeek V4 Flash Free · 5.7s)

---

## User

Master Prompt: Tessera Window Manager Development

Context & Persona:
Act as an expert Systems Engineer and macOS Developer specializing in low-level operating system APIs (CoreGraphics, ApplicationServices) and window management architecture.

Project Overview:
I am building "Tessera", a custom tiling window manager and workspace manager for macOS.
Unlike native macOS Spaces, Tessera will use Virtual Workspaces to bypass Apple's slow, unskippable animations. It will maintain a single large invisible canvas and use a Binary Space Partitioning (BSP) tree to instantly calculate, hide, show, and resize windows when switching contexts or adding new applications.

Architectural Strategy (The "Brain" vs. "Body"):
Because macOS development can be tricky to test rapidly, we are decoupling the logic from the OS.

The Brain (OS-Agnostic): We will build the Layout Engine (BSP tree, vector focus math, and virtual workspace state map) in Python first for rapid prototyping.

The Body (macOS-Specific): Later, we will port this logic to Swift and wire it up to Apple's AXUIElement (Accessibility API) to manipulate actual windows, and CGEventTap to intercept global keyboard shortcuts.

Your Current Task: Phase 1 (The Python Prototype)

I want to start by building the pure mathematical "Brain" of Tessera in Python. We will not touch macOS APIs yet. We are building the data structures and the BSP layout engine.

Please guide me through completing Phase 1, addressing the following defined tasks one by one. Provide the Python code for each step:

Task 1: Core Data Models
Define the base classes: Rect (X, Y, Width, Height) and Window (ID, current Rect).

Task 2: The BSP Tree Node
Create a TreeNode class. It needs to hold a Rect, optionally hold a Window (if it's a leaf node), and have pointers to a left_child and right_child. Define constants for SplitType (Horizontal/Vertical).

Task 3: The Splitting Algorithm (The Engine)
Write the Workspace manager class. Implement the add_window(window) function.

If the workspace is empty, the new window takes the full Monitor Rect.

If it's not empty, the algorithm must find the currently focused leaf node, split its Rect exactly in half (alternating horizontal/vertical), move the existing window into one child node, and put the new window into the other child node.

Task 4: CLI Visualization
Write a simple simulation script where I can define a 1920x1080 monitor, add 3 mock windows sequentially, and print the resulting calculated X, Y, W, H coordinates for each window to the terminal to verify the math works.

Instructions for your response:
Take a deep breath and let's tackle Task 1 and Task 2 first. Show me the Python code, explain the structure, and wait for my confirmation before moving to Task 3. 

---

## Assistant (Plan · Nemotron 3 Ultra Free · 17.6s)

_Thinking:_

The user wants me to help build a tiling window manager called "Tessera" for macOS. They're starting with Phase 1 - a Python prototype of the core layout engine (BSP tree).

They want me to tackle Task 1 and Task 2 first:
1. Core Data Models (Rect, Window classes)
2. BSP Tree Node (TreeNode class with SplitType)

Since I'm in plan mode (read-only), I should provide the Python code for these tasks and explain the structure, then wait for confirmation before moving to Task 3.

Let me write clean, well-structured Python code for Tasks 1 and 2.

# Task 1 & 2: Core Data Models & BSP Tree Node

Here's the Python implementation:

```python
# tessera/core/models.py
from dataclasses import dataclass
from enum import Enum
from typing import Optional


@dataclass
class Rect:
    """Represents a rectangle with x, y, width, height."""
    x: float
    y: float
    width: float
    height: float

    def split_horizontal(self) -> tuple["Rect", "Rect"]:
        """Split rectangle horizontally (top/bottom)."""
        half_height = self.height / 2
        top = Rect(self.x, self.y, self.width, half_height)
        bottom = Rect(self.x, self.y + half_height, self.width, half_height)
        return top, bottom

    def split_vertical(self) -> tuple["Rect", "Rect"]:
        """Split rectangle vertically (left/right)."""
        half_width = self.width / 2
        left = Rect(self.x, self.y, half_width, self.height)
        right = Rect(self.x + half_width, self.y, half_width, self.height)
        return left, right

    def __repr__(self) -> str:
        return f"Rect(x={self.x:.0f}, y={self.y:.0f}, w={self.width:.0f}, h={self.height:.0f})"


@dataclass
class Window:
    """Represents a managed window."""
    id: str
    rect: Optional[Rect] = None

    def __repr__(self) -> str:
        return f"Window(id={self.id}, rect={self.rect})"


class SplitType(Enum):
    HORIZONTAL = "horizontal"  # Top/Bottom split
    VERTICAL = "vertical"      # Left/Right split

    def alternate(self) -> "SplitType":
        return SplitType.VERTICAL if self == SplitType.HORIZONTAL else SplitType.HORIZONTAL


# tessera/core/bsp.py
from dataclasses import dataclass, field
from typing import Optional
from .models import Rect, Window, SplitType


@dataclass
class TreeNode:
    """Node in the Binary Space Partitioning tree."""
    rect: Rect
    window: Optional[Window] = None
    left_child: Optional["TreeNode"] = None
    right_child: Optional["TreeNode"] = None
    split_type: Optional[SplitType] = None
    is_focused: bool = False

    @property
    def is_leaf(self) -> bool:
        return self.left_child is None and self.right_child is None

    def __repr__(self) -> str:
        if self.is_leaf:
            return f"Leaf(window={self.window}, rect={self.rect}, focused={self.is_focused})"
        return f"Internal(split={self.split_type.value}, left={self.left_child}, right={self.right_child})"
```

## Structure Explanation

| File | Purpose |
|------|---------|
| `models.py` | Pure data classes - `Rect` with split helpers, `Window` with ID, `SplitType` enum |
| `bsp.py` | `TreeNode` - holds a `Rect`, optional `Window` (only at leaves), child pointers, split type, focus state |

**Key design decisions:**
- `Rect.split_horizontal()` / `split_vertical()` return two new rects (immutability-friendly)
- `SplitType.alternate()` enables the alternating split pattern
- `TreeNode.is_leaf` property makes tree traversal clean
- Focus tracking lives on the node (needed for Task 3's "find focused leaf")

---

Ready for **Task 3** (Workspace manager with `add_window` algorithm)?

---

## User

ok

---

## Assistant (Plan · Nemotron 3 Ultra Free · 95.1s)

_Thinking:_

The user said "ok" which seems like they want me to proceed with Task 3. But I'm in "Plan Mode" which means I should only read/analyze and create a plan, not execute any code.

Let me re-read the system reminder - it says I'm in READ-ONLY phase and should construct a well-formed plan. But the user already gave me the plan in the master prompt - they want me to implement Task 3 (the Workspace manager with add_window algorithm).

Wait, looking at the context again - the user said "Take a deep breath and let's tackle Task 1 and Task 2 first. Show me the Python code, explain the structure, and wait for my confirmation before moving to Task 3." And I did that. Then they said "ok" which is confirmation to move to Task 3.

But now there's a system reminder saying I'm in Plan Mode and READ-ONLY. This seems contradictory - the user wants me to implement, but the system says I can only plan.

I think the system reminder might be a general instruction that was added, but the user explicitly wants me to continue implementing. Let me check - the user's original request was to "guide me through completing Phase 1, addressing the following defined tasks one by one. Provide the Python code for each step" and they said "wait for my confirmation before moving to Task 3" which they just gave with "ok".

I should probably ask for clarification since there's a conflict between the system reminder (plan mode) and the user's explicit request to continue implementation.

I notice there's a system reminder indicating "Plan Mode - READ-ONLY phase" but you've explicitly confirmed to proceed with Task 3 implementation.

**Clarification needed:** Should I:
1. **Implement Task 3 now** (continue coding the Workspace manager with `add_window` algorithm)
2. **Create a plan first** (per the system reminder's read-only constraint)

The original prompt asked me to "guide you through completing Phase 1... provide the Python code for each step" and you said "wait for my confirmation before moving to Task 3" — which you just gave with "ok".

Which would you prefer?

---

## User

2

---

## Assistant (Plan · Nemotron 3 Ultra Free · 8.3s)

_Thinking:_

The user wants me to create a plan for Task 3 (Workspace manager with add_window algorithm) since we're in plan mode. Let me think through what needs to be implemented.

Task 3 requirements:
1. Workspace manager class
2. `add_window(window)` function
3. If workspace is empty → new window takes full Monitor Rect
4. If not empty → find currently focused leaf node, split its Rect in half (alternating horizontal/vertical), move existing window to one child, put new window in other child

Let me create a clear plan for this.

# Plan for Task 3: Workspace Manager & Splitting Algorithm

## Overview
Implement the `Workspace` class that manages the BSP tree and handles the `add_window` logic with alternating splits.

## Files to Create/Modify

### 1. `tessera/core/workspace.py` (New)
**Class: `Workspace`**
- **Attributes:**
  - `root: Optional[TreeNode]` — root of BSP tree
  - `monitor_rect: Rect` — full screen bounds
  - `next_split_type: SplitType` — tracks alternating split direction (start with HORIZONTAL or VERTICAL)

- **Methods:**
  - `__init__(monitor_rect: Rect, initial_split: SplitType = SplitType.HORIZONTAL)`
  - `add_window(window: Window) -> None` — main algorithm
  - `_find_focused_leaf(node: TreeNode) -> TreeNode` — recursive search
  - `_split_leaf(leaf: TreeNode, new_window: Window) -> None` — performs the split
  - `get_all_windows() -> list[Window]` — helper for visualization
  - `print_tree() -> None` — debug visualization

### 2. `tessera/core/__init__.py` (Update)
Export new `Workspace` class.

## Algorithm: `add_window(window)`

```
add_window(window):
  if root is None:
    window.rect = monitor_rect
    root = TreeNode(rect=monitor_rect, window=window, is_focused=True)
    next_split_type = initial_split.alternate()
    return

  # Find currently focused leaf
  focused_leaf = _find_focused_leaf(root)
  focused_leaf.is_focused = False

  # Split the leaf's rect
  left_rect, right_rect = focused_leaf.rect.split_horizontal() 
  # OR split_vertical() based on next_split_type

  # Create internal node replacing the leaf
  focused_leaf.split_type = next_split_type
  focused_leaf.window = None
  focused_leaf.left_child = TreeNode(rect=left_rect, window=focused_leaf.window_original, is_focused=False)
  focused_leaf.right_child = TreeNode(rect=right_rect, window=new_window, is_focused=True)

  # Update split tracker
  next_split_type = next_split_type.alternate()
```

## Key Design Decisions Needed

| Decision | Options | Recommendation |
|----------|---------|----------------|
| **Initial split direction** | HORIZONTAL vs VERTICAL | HORIZONTAL (top/bottom first) — more natural for reading |
| **Which child gets new window** | Left/Top vs Right/Bottom | New window → Right/Bottom (feels like "append") |
| **Focus behavior** | New window focused vs old window focused | New window focused (matches typical WM behavior) |
| **Tree mutation strategy** | Replace leaf in-place vs rebuild | In-place mutation (simpler, matches BSP semantics) |

## Questions for You

1. **Initial split direction**: Horizontal (top/bottom) or Vertical (left/right) first?
2. **New window placement**: Should new windows go to right/bottom child, or left/top?
3. **Focus after split**: Should the *new* window be focused, or the *existing* one?
4. **Gap/gutter support**: Should we plan for gaps between windows now, or add later?

---

## User

Initial Split direction should be Vertical
For new window placement right/bottom
Focus after the split should be current window
Gap support should be default, add give configuration option. 

---

## Assistant (Plan · Nemotron 3 Ultra Free · 33.6s)

_Thinking:_

The user has confirmed the plan details and I'm in plan mode. Let me create a comprehensive plan for Task 3 based on their decisions:

1. Initial split: VERTICAL (left/right)
2. New window placement: right/bottom child
3. Focus after split: current/existing window (not the new one)
4. Gap support: default with configuration option

I need to create a detailed implementation plan that can be executed once they give the go-ahead.

# Task 3 Implementation Plan: Workspace Manager

Based on your decisions, here's the detailed plan:

## Configuration
- **Initial split**: `VERTICAL` (left/right)
- **New window → right/bottom child**
- **Focus retention**: existing window stays focused after split
- **Gaps**: enabled by default, configurable

---

## Files to Create/Modify

### 1. `tessera/core/config.py` (New)
```python
@dataclass
class TesseraConfig:
    gap_size: int = 8           # pixels between windows
    outer_gap: int = 16         # pixels from screen edge
    initial_split: SplitType = SplitType.VERTICAL
    new_window_focus: bool = False  # False = keep focus on existing
```
- Single source of truth for all layout parameters
- Passed to `Workspace` constructor

### 2. `tessera/core/workspace.py` (New)
```python
class Workspace:
    def __init__(self, monitor_rect: Rect, config: TesseraConfig = None)
    def add_window(self, window: Window) -> None
    def remove_window(self, window_id: str) -> Optional[Window]
    def focus_window(self, window_id: str) -> bool
    def get_layout() -> list[tuple[Window, Rect]]  # for rendering
    def _find_focused_leaf(node) -> TreeNode
    def _split_leaf(leaf, new_window, split_type)
    def _apply_gaps(rect) -> Rect  # shrinks rect by gap_size
    def _recalculate_tree()  # reapply gaps after structural changes
```

**`add_window` Algorithm:**
```
1. If empty: 
   - window.rect = apply_gaps(monitor_rect)
   - root = TreeNode(window=window, is_focused=True)
   - next_split = config.initial_split
   - return

2. Find focused leaf (DFS)
3. Unfocus it (will refocus after split per your spec)
4. Split leaf.rect using next_split (apply gaps to children)
5. Convert leaf to internal node:
   - leaf.split_type = next_split
   - leaf.window = None
   - leaf.left_child = TreeNode(existing_window, rect=left, is_focused=True)
   - leaf.right_child = TreeNode(new_window, rect=right, is_focused=False)
6. next_split = next_split.alternate()
```

**Gap Application:**
- `monitor_rect` → shrink by `outer_gap` on all sides = "usable area"
- Each split: children get `gap_size/2` margin on split edge
- Leaf windows: final rect = node.rect shrunk by `gap_size/2` all sides

### 3. `tessera/core/__init__.py`
Export: `Workspace`, `TesseraConfig`

---

## Test Script (Task 4 Preview)
`scripts/test_layout.py`:
```python
monitor = Rect(0, 0, 1920, 1080)
config = TesseraConfig(gap_size=8, outer_gap=16, initial_split=SplitType.VERTICAL)
ws = Workspace(monitor, config)

ws.add_window(Window("A"))  # full screen minus outer gaps
ws.add_window(Window("B"))  # split vertical, A left, B right
ws.add_window(Window("C"))  # split horizontal on focused (A), A top, C bottom

print_layout(ws.get_layout())
```

Expected output (approximate with gaps):
```
Window A: x=16, y=16, w=944, h=520
Window B: x=976, y=16, w=944, h=1048
Window C: x=16, y=552, w=944, h=520
```

---

## Open Questions

1. **Gap distribution on split**: When splitting a leaf with gaps already applied, do we:
   - **Option A**: Split the *gapped* rect, then re-apply gaps to children (gaps compound)
   - **Option B**: Split the *original* rect, apply gaps fresh to children (consistent gaps)

2. **Window removal**: Should removing a window merge its sibling back to parent (collapse tree), or leave empty space?

3. **Focus traversal**: For future `focus_next/prev` — should we implement directional focus (left/right/up/down) now or defer?

---

Ready to implement when you confirm. Which gap distribution approach (A or B)?

---

## User

A

---

## Assistant (Plan · Nemotron 3 Ultra Free · 77.2s)

_Thinking:_

The user selected "A" for gap distribution - they want Option A: split the gapped rect, then re-apply gaps to children (gaps compound).

Now I have all the decisions needed to finalize the plan. Let me summarize the complete plan for Task 3 and ask if they want me to proceed with implementation.

Plan finalized with your choices:

## Summary: Task 3 Implementation Plan

| Decision | Choice |
|----------|--------|
| Initial split | `VERTICAL` (left/right) |
| New window placement | Right/Bottom child |
| Focus after split | **Existing** window stays focused |
| Gap support | Enabled by default, configurable |
| Gap distribution | **Option A**: Compound gaps (split gapped rect, re-apply to children) |

---

## Implementation Files

### `tessera/core/config.py`
```python
```python
@dataclass
class TesseraConfig:
    gap_size: int = 8
    outer_gap: int = 16
    initial_split: SplitType = SplitType.VERTICAL
    new_window_focus: bool = False
```

### `tessera/core/workspace.py`
- `Workspace(monitor_rect: Rect, config: TesseraConfig = None)`
- `add_window(window: Window)` — core algorithm with compound gap logic
- `_apply_gaps(rect: Rect) -> Rect` — shrinks rect by gap_size/2 each side
- `_split_leaf(leaf, new_window, split_type)` — creates internal node, applies gaps to children
- `_find_focused_leaf(node)` — DFS search
- `get_layout() -> list[tuple[Window, Rect]]` — for Task 4 visualization

### `tessera/core/__init__.py`
- Export `Workspace`, `TesseraConfig`

---

## Gap Math (Option A - Compound)

```
Monitor: 1920x1080
Outer gap: 16px → Usable: 1888x1048 at (16,16)

Add Window A:
  A.rect = apply_gaps(usable) = shrink by 4px each side
  A: x=20, y=20, w=1880, h=1040

Add Window B (VERTICAL split on A):
  Split A's rect (1880x1040) vertically → left: 940x1040, right: 940x1040
  Apply gaps to each child (shrink by 4px):
  A: x=20, y=20, w=932, h=1032
  B: x=964, y=20, w=932, h=1032

Add Window C (HORIZONTAL split on A - focused):
  Split A's rect (932x1032) horizontally → top: 932x516, bottom: 932x516
  Apply gaps:
  A: x=20, y=20, w=924, h=508
  C: x=20, y=540, w=924, h=508
  B unchanged: x=964, y=20, w=932, h=1032
```

---

## Ready for Implementation

Shall I proceed with coding Task 3 (and Task 4 test script)?

---

