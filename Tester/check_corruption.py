import cv2
from typing import Literal
from pathlib import Path

PROTOCOL: Literal["rist", "rtp", "srt", "udp"] = "udp"
SCENARIO: Literal["Best", "Average", "Worst"] = "Worst"
video_path = Path(f"./Runs/{PROTOCOL}/{SCENARIO}/out.mp4")

cap = cv2.VideoCapture(video_path)
if not cap.isOpened():
    print("Error: Cannot open video file.")
    raise SystemExit(1)

frame_skip = 30
frame_index = 0
current_index = 0
decisions = []

window_name = "Frame Review"
cv2.namedWindow(window_name, cv2.WND_PROP_FULLSCREEN)
cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)

print(
    "Instructions:\n"
    "'c' - Mark as corrupted\n"
    "'n' - Mark as not corrupted\n"
    "'u' - Undo last decision\n"
    "'q' - Quit and show results"
)

buffered_frames = []
running = True

while running:
    ret, frame = cap.read()
    if not ret:
        print("End of video or cannot read frame.")
        break

    if current_index == frame_index:
        cv2.imshow(window_name, frame)
        buffered_frames.append((frame_index, frame))

        while True:
            key = cv2.waitKey(0) & 0xFF

            if key == ord("c"):
                decisions.append((frame_index, "corrupted"))
                frame_index += frame_skip
            elif key == ord("n"):
                decisions.append((frame_index, "not_corrupted"))
                frame_index += frame_skip
            elif key == ord("u"):
                if decisions:
                    print("Undoing last decision.")
                    decisions.pop()
                    if len(buffered_frames) >= 2:
                        buffered_frames.pop()  # Remove last
                        frame_index = buffered_frames[-1][0]
                        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
                        current_index = (
                            frame_index - 1
                        )  # because next read will increment it
                    else:
                        print("Nothing to undo.")
                        frame_index = 0
                        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        current_index = -1
                        buffered_frames.clear()
                else:
                    print("No decisions to undo.")
            elif key == ord("q"):
                print("Quitting...")
                running = False
            else:
                print("Invalid key. Use 'c', 'n', 'u', or 'q'.")
                continue
            break
    current_index += 1

cap.release()
cv2.destroyAllWindows()

corrupted_count = sum(1 for _, decision in decisions if decision == "corrupted")
total_reviewed = len(decisions)

print(
    f"\nReview Complete.\nCorrupted Frames: {corrupted_count}\nTotal Frames Reviewed: {total_reviewed}"
)


print(f"Corruption Percentage: {corrupted_count / total_reviewed}")
