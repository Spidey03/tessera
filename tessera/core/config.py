from dataclasses import dataclass, field
from .models import SplitType


@dataclass
class TesseraConfig:
    gap_size: int = 8
    outer_gap: int = 16
    initial_split: SplitType = SplitType.VERTICAL
    new_window_focus: bool = False
