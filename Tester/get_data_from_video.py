import cv2
from pathlib import Path
from cv2.typing import MatLike
import pytesseract as pyt


def parse_time(time: str) -> int | None:
    split_data = time.split(":")
    if len(split_data) != 3:
        return None
    hours, minutes, seconds_and_milliseconds = split_data

    if len(hours) != 2 or len(minutes) != 2:
        return None

    split_seconds = seconds_and_milliseconds.split(".")

    if len(split_seconds) != 2:
        return None

    seconds, milliseconds = split_seconds

    if len(seconds) != 2 or len(milliseconds) != 3:
        return None

    try:
        hours = int(hours)
        minutes = int(minutes)
        seconds = int(seconds)
        milliseconds = int(milliseconds)
    except Exception:
        return None

    if hours < 12 and minutes < 60 and seconds < 60 and milliseconds < 1000:
        latency = (hours * 60 * 60 + minutes * 60 + seconds) * 1000 + milliseconds
        if latency >= 0:
            return latency
        else:
            return None

    return None


def get_latency(frame: MatLike) -> float | None:
    converted = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    converted = cv2.threshold(converted, 127, 255, cv2.THRESH_BINARY)[1]
    converted = cv2.bitwise_not(converted)

    original_time_image = converted[0:60, 125:425]
    new_time_image = converted[90:150, 125:425]

    config = "--psm 6 --oem 1 -c tessedit_char_whitelist=0123456789:."
    original_time: str = pyt.image_to_string(original_time_image, config=config)
    new_time: str = pyt.image_to_string(new_time_image, config=config)

    original_time = original_time.strip()
    new_time = new_time.strip()

    parse_original_time = parse_time(original_time)
    parse_new_time = parse_time(new_time)

    if parse_original_time is not None and parse_new_time is not None:
        return parse_new_time - parse_original_time

    return None


def create_latency_measurements(folder: Path):
    mp4_path = folder / "out.mp4"
    output_path = folder / "latency.csv"
    video = cv2.VideoCapture(str(mp4_path))
    frame_count = -1

    with open(output_path, "w") as f:
        while True:
            frame_count += 1
            ret, frame = video.read()
            if not ret:
                break

            if frame_count % 30 != 0:
                continue

            latency = get_latency(frame)
            f.write(f"{frame_count},{latency}\n")
            if frame_count % 100 == 0:
                print(
                    f"Processing {folder}. Frames processed: {frame_count}/18000 frames"
                )


root = Path("./Runs/")

# Walk through all the folders in the root directory
for path, _, files in root.walk():
    if "out.mp4" not in files:
        continue

    create_latency_measurements(path)
