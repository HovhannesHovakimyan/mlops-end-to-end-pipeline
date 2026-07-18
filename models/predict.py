"""
Model inference service.
Loads trained model and provides prediction endpoint.
"""

import os
import pickle
import logging
import json
import numpy as np
import boto3
from flask import Flask, request, jsonify
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio.minio:9000")
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID", "minioadmin")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "minioadmin")
MODEL_REGISTRY_PATH = os.getenv("MODEL_REGISTRY_PATH", "/models")

# Initialize S3 client
s3_client = boto3.client(
    's3',
    endpoint_url=MINIO_ENDPOINT,
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY
)

# Global model and scaler
model = None
scaler = None
model_version = None

def load_model():
    """Load latest model and scaler from MinIO."""
    global model, scaler, model_version

    try:
        logger.info("Loading model from MinIO...")

        # Download model
        model_buffer = s3_client.get_object(
            Bucket='model-registry',
            Key='churn-model/latest/model.pkl'
        )
        model = pickle.load(model_buffer['Body'])

        # Download scaler
        scaler_buffer = s3_client.get_object(
            Bucket='model-registry',
            Key='churn-model/latest/scaler.pkl'
        )
        scaler = pickle.load(scaler_buffer['Body'])

        model_version = datetime.now().isoformat()
        logger.info(f"Model loaded successfully. Version: {model_version}")

    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        logger.warning("Using dummy model for testing")
        # Use dummy model for testing if MinIO is unavailable
        model = None
        scaler = None

@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    if model is None:
        return jsonify({"status": "unhealthy", "reason": "Model not loaded"}), 503
    return jsonify({"status": "healthy", "model_version": model_version}), 200

@app.route("/metrics", methods=["GET"])
def metrics():
    """Prometheus metrics endpoint."""
    # Basic metrics for monitoring
    return """
# HELP model_inference_requests_total Total inference requests
# TYPE model_inference_requests_total counter
model_inference_requests_total 0

# HELP model_inference_latency_seconds Inference latency in seconds
# TYPE model_inference_latency_seconds histogram
model_inference_latency_seconds_bucket{le="0.01"} 0
model_inference_latency_seconds_bucket{le="0.1"} 0
model_inference_latency_seconds_bucket{le="1"} 0
model_inference_latency_seconds_bucket{le="+Inf"} 0
""", 200, {"Content-Type": "text/plain"}

@app.route("/predict", methods=["POST"])
def predict():
    """Inference endpoint."""
    if model is None:
        return jsonify({"error": "Model not loaded"}), 503

    try:
        data = request.json

        # Extract features
        features = np.array([[
            data.get('tenure', 0),
            data.get('monthly_charges', 0),
            data.get('total_charges', 0),
            data.get('contract_length', 0),
            data.get('internet_service', 0),
            data.get('monthly_services', 0),
        ]])

        # Scale features
        features_scaled = scaler.transform(features)

        # Predict
        prediction = model.predict(features_scaled)[0]
        probability = model.predict_proba(features_scaled)[0]

        return jsonify({
            "prediction": int(prediction),
            "churn_probability": float(probability[1]),
            "no_churn_probability": float(probability[0]),
            "model_version": model_version,
            "timestamp": datetime.now().isoformat()
        }), 200

    except Exception as e:
        logger.error(f"Prediction error: {e}")
        return jsonify({"error": str(e)}), 400

@app.route("/v1/models/churn-predictor:predict", methods=["POST"])
def kserve_predict():
    """KServe compatible predict endpoint."""
    if model is None:
        return jsonify({"error": "Model not loaded"}), 503

    try:
        data = request.json

        # KServe format: {"instances": [[...]]}
        instances = data.get("instances", [])

        predictions = []
        for instance in instances:
            features = np.array([instance])
            features_scaled = scaler.transform(features)
            prediction = model.predict(features_scaled)[0]
            probability = model.predict_proba(features_scaled)[0]

            predictions.append({
                "prediction": int(prediction),
                "churn_probability": float(probability[1]),
                "no_churn_probability": float(probability[0])
            })

        return jsonify({"predictions": predictions}), 200

    except Exception as e:
        logger.error(f"KServe prediction error: {e}")
        return jsonify({"error": str(e)}), 400

if __name__ == "__main__":
    load_model()
    app.run(host="0.0.0.0", port=5000, debug=False)
