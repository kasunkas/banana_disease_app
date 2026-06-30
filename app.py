import os
import uuid
import numpy as np
from PIL import Image
from flask import Flask, jsonify, render_template, request
from werkzeug.utils import secure_filename
from keras.models import load_model

app = Flask(__name__)

# Configuration
UPLOAD_FOLDER = "uploads"
MODEL_PATH = "model/banana_disease_model.h5"
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg"}

app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# Load model once at startup
print("Loading model...")
model = load_model(MODEL_PATH, compile=False)
print("Model loaded successfully!")

# Update these labels to match your model output order
class_names = [
    "Black_Sigatoka",
    "Cordana",
    "Healthy",
    "Panama_Disease",
    "Moko_Disease",
    "Pestalotiopsis",
    "Yellow_Sigatoka",
]


def allowed_file(filename: str) -> bool:
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


@app.route("/")
def home():
    return render_template("index.html")


@app.route("/predict", methods=["POST"])
def predict():
    if "file" not in request.files:
        return jsonify({"error": "No file uploaded"}), 400

    file = request.files["file"]

    if file.filename == "":
        return jsonify({"error": "No file selected"}), 400

    if not allowed_file(file.filename):
        return jsonify({"error": "Invalid file type. Use png, jpg, or jpeg."}), 400

    safe_name = secure_filename(file.filename)
    unique_name = f"{uuid.uuid4().hex}_{safe_name}"
    filepath = os.path.join(app.config["UPLOAD_FOLDER"], unique_name)
    file.save(filepath)

    try:
        # Preprocess image to model input shape
        img = Image.open(filepath).convert("RGB")
        img = img.resize((224, 224))
        img_array = np.array(img, dtype=np.float32) / 255.0
        img_array = np.expand_dims(img_array, axis=0)

        predictions = model.predict(img_array, verbose=0)

        predicted_index = int(np.argmax(predictions))
        predicted_class = class_names[predicted_index]
        confidence = float(np.max(predictions)) * 100.0

        probabilities = {
            class_names[i]: round(float(predictions[0][i]) * 100.0, 2)
            for i in range(min(len(class_names), predictions.shape[1]))
        }

        # Print the prediction result in the terminal
        print(f"\n--- Prediction Result ---")
        print(f"File: {file.filename}")
        print(f"Predicted Class: {predicted_class}")
        print(f"Confidence: {confidence:.2f}%")
        print(f"All Probabilities: {probabilities}")
        print("-------------------------\n")

        return jsonify(
            {
                "class": predicted_class,
                "confidence": round(confidence, 2),
                "all_probabilities": probabilities,
            }
        )

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


if __name__ == "__main__":
    app.run(debug=True, port=5000)
