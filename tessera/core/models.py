from dataclasses import dataclass
from enum import Enum
from typing import Optional


@dataclass
class Rect:
    x: float
    y: float
    width: float
    height: float

    def split_horizontal(self) -> tuple["Rect", "Rect"]:
        half_height = self.height / 2
        top = Rect(self.x, self.y, self.width, half_height)
        bottom = Rect(self.x, self.y + half_height, self.width, half_height)
        return top, bottom

    def split_vertical(self) -> tuple["Rect", "Rect"]:
        half_width = self.width / 2
        left = Rect(self.x, self.y, half_width, self.height)
        right = Rect(self.x + half_width, self.y, half_width, self.height)
        return left, right

    def inset(self, amount: float) -> "Rect":
        return Rect(
            self.x + amount,
            self.y + amount,
            self.width - 2 * amount,
            self.height - 2 * amount,
        )

    def __repr__(self) -> str:
        return f"Rect(x={self.x:.0f}, y={self.y:.0f}, w={self.width:.0f}, h={self.height:.0f})"


@dataclass
class Window:
    id: str
    rect: Optional[Rect] = None

    def __repr__(self) -> str:
        return f"Window(id={self.id}, rect={self.rect})"


class SplitType(Enum):
    HORIZONTAL = "horizontal"
    VERTICAL = "vertical"

    def alternate(self) -> "SplitType":
        return SplitType.VERTICAL if self == SplitType.HORIZONTAL else SplitType.HORIZONTAL
