"""
Main training pipeline orchestration.
Handles data loading, feature engineering, model training, and registry.
"""

import os
import pickle
import numpy as np
import pandas as pd
import logging
from datetime import datetime
from pathlib import Path

import mlflow
import mlflow.sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score
import boto3

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# MLflow configuration
MLFLOW_TRACKING_URI = os.getenv("MLFLOW_TRACKING_URI", "http://mlflow.mlflow:5000")
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio.minio:9000")
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID", "minioadmin")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "minioadmin")

# Initialize MLflow
mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
mlflow.set_experiment("churn-prediction")

# Initialize S3 client for MinIO
s3_client = boto3.client(
    's3',
    endpoint_url=MINIO_ENDPOINT,
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY
)

def create_sample_data(n_samples=1000):
    """Generate synthetic customer churn data for demo purposes."""
    np.random.seed(42)

    data = {
        'tenure': np.random.randint(1, 72, n_samples),
        'monthly_charges': np.random.uniform(20, 120, n_samples),
        'total_charges': np.random.uniform(100, 8000, n_samples),
        'contract_length': np.random.choice([0, 1, 2], n_samples),  # month-to-month, 1-year, 2-year
        'internet_service': np.random.choice([0, 1, 2], n_samples),  # DSL, Fiber, No
        'monthly_services': np.random.randint(1, 8, n_samples),
    }

    df = pd.DataFrame(data)

    # Generate target: probability of churn increases with fewer services and shorter tenure
    churn_prob = (
        0.3 * (1 - df['tenure'] / 72) +  # Newer customers more likely to churn
        0.2 * (df['monthly_services'] < 3) +  # Fewer services → churn
        0.1 * (df['contract_length'] == 0)  # Month-to-month → more churn
    )

    df['churn'] = (np.random.random(n_samples) < churn_prob).astype(int)

    return df

def load_data():
    """Load training data from MinIO or create sample data."""
    logger.info("Loading training data...")

    try:
        # Try to load from MinIO
        response = s3_client.get_object(Bucket='training-data', Key='churn_data.csv')
        df = pd.read_csv(response['Body'])
        logger.info(f"Loaded {len(df)} rows from MinIO")
    except Exception as e:
        logger.warning(f"Could not load from MinIO: {e}. Using sample data.")
        df = create_sample_data(1000)

        # Save to MinIO for future runs
        try:
            s3_client.head_bucket(Bucket='training-data')
        except:
            s3_client.create_bucket(Bucket='training-data')

        csv_buffer = df.to_csv(index=False)
        s3_client.put_object(Bucket='training-data', Key='churn_data.csv', Body=csv_buffer)
        logger.info("Saved sample data to MinIO")

    return df

def preprocess_data(df):
    """Prepare data for model training."""
    logger.info("Preprocessing data...")

    X = df.drop('churn', axis=1)
    y = df['churn']

    # Train/test split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # Feature scaling
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    logger.info(f"Train set: {X_train_scaled.shape}, Test set: {X_test_scaled.shape}")

    return X_train_scaled, X_test_scaled, y_train, y_test, scaler

def train_model(X_train, X_test, y_train, y_test, scaler):
    """Train Random Forest model with MLflow tracking."""
    logger.info("Training model...")

    with mlflow.start_run(description="Customer churn prediction model"):
        # Hyperparameters
        n_estimators = 100
        max_depth = 15
        random_state = 42

        # Log parameters
        mlflow.log_param("n_estimators", n_estimators)
        mlflow.log_param("max_depth", max_depth)
        mlflow.log_param("random_state", random_state)

        # Train model
        model = RandomForestClassifier(
            n_estimators=n_estimators,
            max_depth=max_depth,
            random_state=random_state,
            n_jobs=-1
        )
        model.fit(X_train, y_train)

        # Evaluate on test set
        y_pred = model.predict(X_test)
        y_pred_proba = model.predict_proba(X_test)[:, 1]

        # Calculate metrics
        accuracy = accuracy_score(y_test, y_pred)
        precision = precision_score(y_test, y_pred)
        recall = recall_score(y_test, y_pred)
        f1 = f1_score(y_test, y_pred)
        roc_auc = roc_auc_score(y_test, y_pred_proba)

        # Log metrics
        mlflow.log_metric("accuracy", accuracy)
        mlflow.log_metric("precision", precision)
        mlflow.log_metric("recall", recall)
        mlflow.log_metric("f1_score", f1)
        mlflow.log_metric("roc_auc", roc_auc)

        logger.info(f"Model metrics: Accuracy={accuracy:.4f}, Precision={precision:.4f}, "
                   f"Recall={recall:.4f}, F1={f1:.4f}, ROC-AUC={roc_auc:.4f}")

        # Log model
        mlflow.sklearn.log_model(model, "model", registered_model_name="churn-predictor")

        # Log scaler as artifact
        scaler_path = "/tmp/scaler.pkl"
        with open(scaler_path, 'wb') as f:
            pickle.dump(scaler, f)
        mlflow.log_artifact(scaler_path)

        # Log tags
        mlflow.set_tag("stage", "production")
        mlflow.set_tag("team", "mlops")

        run_id = mlflow.active_run().info.run_id
        logger.info(f"Model logged with run_id: {run_id}")

        return model, run_id

def save_to_minio(model, scaler, run_id):
    """Save trained model and scaler to MinIO."""
    logger.info("Saving artifacts to MinIO...")

    # Create model registry bucket if not exists
    try:
        s3_client.head_bucket(Bucket='model-registry')
    except:
        s3_client.create_bucket(Bucket='model-registry')

    # Save model
    model_path = f"/tmp/churn_model_{run_id}.pkl"
    with open(model_path, 'wb') as f:
        pickle.dump(model, f)

    with open(model_path, 'rb') as f:
        s3_client.upload_fileobj(
            f,
            'model-registry',
            f'churn-model/{run_id}/model.pkl'
        )

    # Save scaler
    scaler_path = f"/tmp/scaler_{run_id}.pkl"
    with open(scaler_path, 'wb') as f:
        pickle.dump(scaler, f)

    with open(scaler_path, 'rb') as f:
        s3_client.upload_fileobj(
            f,
            'model-registry',
            f'churn-model/{run_id}/scaler.pkl'
        )

    # Create symbolic link to "latest"
    try:
        s3_client.copy_object(
            CopySource={'Bucket': 'model-registry', 'Key': f'churn-model/{run_id}/model.pkl'},
            Bucket='model-registry',
            Key='churn-model/latest/model.pkl'
        )
        s3_client.copy_object(
            CopySource={'Bucket': 'model-registry', 'Key': f'churn-model/{run_id}/scaler.pkl'},
            Bucket='model-registry',
            Key='churn-model/latest/scaler.pkl'
        )
    except Exception as e:
        logger.warning(f"Could not update latest symbolic link: {e}")

    logger.info(f"Model saved to MinIO at churn-model/{run_id}/")

def main():
    """Main training pipeline."""
    logger.info("="*50)
    logger.info("Starting ML Pipeline Execution")
    logger.info(f"Timestamp: {datetime.now().isoformat()}")
    logger.info("="*50)

    try:
        # Load and preprocess data
        df = load_data()
        X_train, X_test, y_train, y_test, scaler = preprocess_data(df)

        # Train model
        model, run_id = train_model(X_train, X_test, y_train, y_test, scaler)

        # Save to MinIO
        save_to_minio(model, scaler, run_id)

        logger.info("="*50)
        logger.info("Pipeline completed successfully!")
        logger.info(f"Model registered: churn-predictor")
        logger.info(f"Run ID: {run_id}")
        logger.info("="*50)

    except Exception as e:
        logger.error(f"Pipeline failed: {e}", exc_info=True)
        raise

if __name__ == "__main__":
    main()
