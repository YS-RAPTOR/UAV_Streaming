from typing import Literal
import cv2
from pathlib import Path

PROTOCOL: Literal["rist", "rtp", "srt", "udp"] = "rtp"
SCENARIO: Literal["Best", "Average", "Worst"] = "Worst"


def main():
    cap = cv2.VideoCapture(Path(f"./Runs/{PROTOCOL}/{SCENARIO}/out.mp4"))

    if not cap.isOpened():
        print("Error: Cannot open video.")
        return

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"Total frames in video: {total_frames}")

    current_frame = 0

    while True:
        user_input = input("Enter frame number to display (or 'q' to quit): ").strip()
        if user_input.lower() == "q":
            break

        if not user_input.isdigit():
            print("Please enter a valid number.")
            continue

        requested_frame = int(user_input)

        if requested_frame >= total_frames or requested_frame < 0:
            print("Frame number out of bounds.")
            continue

        # Seek only if the frame is ahead (assumes increasing order mostly)
        if requested_frame < current_frame:
            cap.set(cv2.CAP_PROP_POS_FRAMES, requested_frame)
        else:
            while current_frame < requested_frame:
                ret, _ = cap.read()
                current_frame += 1

        ret, frame = cap.read()
        current_frame += 1

        if not ret:
            print("Failed to read the frame.")
            continue

        cv2.imshow("Frame", frame)
        print(
            f"Displaying frame {requested_frame}. Press any key in the window to continue."
        )
        cv2.waitKey(0)
        cv2.destroyAllWindows()

    cap.release()


if __name__ == "__main__":
    main()
