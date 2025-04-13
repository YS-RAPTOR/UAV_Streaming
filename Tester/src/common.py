from dataclasses import dataclass
from abc import ABC, abstractmethod
from typing import Tuple
from random import Random
import math


class Provider(ABC):
    @abstractmethod
    def get(self) -> float:
        pass

    @abstractmethod
    def get_int(self) -> int:
        pass


class ConstantProvider(Provider):
    def __init__(self, value: float):
        self.value = value

    def get(self) -> float:
        return self.value

    def get_int(self) -> int:
        return int(self.value)


class RandomExpovariate(Provider):
    def __init__(self, seed: int, lam: int, start_value: int):
        self.rng = Random(seed)
        self.start_value = start_value
        self.lam = lam

    def get(self) -> float:
        return self.rng.expovariate(self.lam) + self.start_value

    def get_int(self) -> int:
        return math.floor(self.get())


Address = Tuple[str, int]


@dataclass
class Settings:
    bandwidth: Provider  # Bytes per second
    latency: Provider  # seconds
    packet_loss_rate: Provider  # percentage [0-1]
    packet_corruption_rate: Provider  # percentage [0-1]
    no_of_packet_corruptions: Provider


@dataclass
class Packet:
    data: bytes
    send_address: Address
    time: float | None = None
