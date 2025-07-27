import json
import math

# Load the JSON data
with open("/Users/evanboyle/Documents/GitHub/VRC-RoboScore/VRC RoboScore/Modules/Camera/Modes/Video/VexFieldAnnotations.json", "r") as f:
    data = json.load(f)

objects = data["objects"]

# Helper functions
def distance(p1, p2):
    return math.hypot(p1["x"] - p2["x"], p1["y"] - p2["y"])

def get_goal_leg_centers():
    return {obj["id"]: obj["center"] for obj in objects if obj["type"] == "Goal Leg"}

def get_long_goals():
    return [obj for obj in objects if obj["type"] == "Long Goal"]

def get_short_goals():
    return [obj for obj in objects if obj["type"] == "Short Goal"]

# 1. Horizontal pairs: (1,2) and (3,4)
goal_leg_centers = get_goal_leg_centers()
long_goals = get_long_goals()
short_goals = get_short_goals()

horizontal_pairs = [(1,2), (3,4)]
vertical_pairs = [(1,4), (2,3)]

print("Horizontal Goal Leg Pairs Analysis:")
for pair in horizontal_pairs:
    c1, c2 = goal_leg_centers[pair[0]], goal_leg_centers[pair[1]]
    leg_dist = distance(c1, c2)
    # Find nearest long goal (by center y value)
    mid_y = (c1["y"] + c2["y"]) / 2
    long_goal_dists = []
    for lg in long_goals:
        ep1, ep2 = lg["endpoints"]
        long_goal_len = distance(ep1, ep2)
        long_goal_mid_y = (ep1["y"] + ep2["y"]) / 2
        long_goal_dists.append((abs(long_goal_mid_y - mid_y), long_goal_len))
    nearest_long_goal_len = min(long_goal_dists, key=lambda x: x[0])[1]
    ratio = leg_dist / nearest_long_goal_len if nearest_long_goal_len else None
    print(f"  Pair {pair}: Leg center distance = {leg_dist:.2f}, Nearest long goal length = {nearest_long_goal_len:.2f}, Ratio = {ratio:.4f}")

print("\nVertical Goal Leg Pairs Analysis:")
vertical_heights = []
for pair in vertical_pairs:
    c1, c2 = goal_leg_centers[pair[0]], goal_leg_centers[pair[1]]
    height = abs(c1["y"] - c2["y"])
    vertical_heights.append(height)
    print(f"  Pair {pair}: Vertical height difference = {height:.2f}")

avg_height_y = sum(vertical_heights) / len(vertical_heights)
print(f"\nAverage vertical height Y between pairs: {avg_height_y:.2f}")

# Polygon bounds for long goals
long_goal_ys = [ep["y"] for lg in long_goals for ep in lg["endpoints"]]
long_goal_xs = [ep["x"] for lg in long_goals for ep in lg["endpoints"]]
min_y, max_y = min(long_goal_ys), max(long_goal_ys)
min_x, max_x = min(long_goal_xs), max(long_goal_xs)

print("\nShort Goal Endpoints Height/Width % Analysis:")
for sg in short_goals:
    for i, ep in enumerate(sg["endpoints"]):
        y_pct = (ep["y"] - min_y) / (max_y - min_y) * 100 if max_y != min_y else None
        x_pct = (ep["x"] - min_x) / (max_x - min_x) * 100 if max_x != min_x else None
        print(f"  Short Goal {sg['id']} Endpoint {i+1}: Y % = {y_pct:.2f}, X % = {x_pct:.2f}")
