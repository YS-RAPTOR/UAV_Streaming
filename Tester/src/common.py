from dataclasses import dataclass
from abc import ABC, abstractmethod
from typing import Tuple


class Provider(ABC):
    @abstractmethod
    def get(self) -> float:
        pass


class ConstantProvider(Provider):
    def __init__(self, value: float):
        self.value = value

    def get(self) -> float:
        return self.value


Address = Tuple[str, int]


@dataclass
class Settings:
    bandwidth: Provider  # Bytes per second
    latency: Provider  # milliseconds
    packet_loss_rate: Provider  # percentage [0-1]
    packet_corruption_rate: Provider  # percentage [0-1]


@dataclass
class Packet:
    data: bytes
    send_address: Address
    time: float | None = None
