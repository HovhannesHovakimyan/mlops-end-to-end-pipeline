"""
Test cases for model training and inference.
"""

import pytest
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler


class TestDataPreprocessing:
    """Test data preprocessing functions."""

    def test_create_sample_data(self):
        """Test sample data generation."""
        from pipelines.train_pipeline import create_sample_data

        df = create_sample_data(100)
        assert len(df) == 100
        assert 'churn' in df.columns
        assert df['churn'].isin([0, 1]).all()

    def test_preprocessing_shapes(self):
        """Test preprocessing returns correct shapes."""
        from pipelines.train_pipeline import create_sample_data, preprocess_data

        df = create_sample_data(100)
        X_train, X_test, y_train, y_test, scaler = preprocess_data(df)

        # Check shapes
        assert X_train.shape[0] + X_test.shape[0] == len(df)
        assert X_train.shape[1] == X_test.shape[1]  # Same features
        assert len(y_train) + len(y_test) == len(df)


class TestModelTraining:
    """Test model training functions."""

    def test_model_creation(self):
        """Test RandomForest model creation."""
        model = RandomForestClassifier(n_estimators=10, random_state=42)
        assert model is not None
        assert model.n_estimators == 10

    def test_model_training(self):
        """Test model training on synthetic data."""
        # Create synthetic data
        X_train = np.random.rand(100, 6)
        y_train = np.random.randint(0, 2, 100)

        # Train model
        model = RandomForestClassifier(n_estimators=10, random_state=42)
        model.fit(X_train, y_train)

        # Check model is trained
        assert hasattr(model, 'n_classes_')
        assert model.n_classes_ == 2

    def test_model_prediction(self):
        """Test model prediction."""
        X_train = np.random.rand(100, 6)
        y_train = np.random.randint(0, 2, 100)

        model = RandomForestClassifier(n_estimators=10, random_state=42)
        model.fit(X_train, y_train)

        # Make predictions
        X_test = np.random.rand(10, 6)
        predictions = model.predict(X_test)

        assert len(predictions) == len(X_test)
        assert predictions.dtype in [np.int64, np.int32]
        assert np.all(np.isin(predictions, [0, 1]))

    def test_probability_predictions(self):
        """Test probability predictions."""
        X_train = np.random.rand(100, 6)
        y_train = np.random.randint(0, 2, 100)

        model = RandomForestClassifier(n_estimators=10, random_state=42)
        model.fit(X_train, y_train)

        X_test = np.random.rand(10, 6)
        proba = model.predict_proba(X_test)

        assert proba.shape == (len(X_test), 2)
        assert np.all(proba >= 0) and np.all(proba <= 1)
        assert np.allclose(proba.sum(axis=1), 1.0)


class TestFeatureScaling:
    """Test feature scaling."""

    def test_scaler_creation(self):
        """Test StandardScaler creation."""
        scaler = StandardScaler()
        assert scaler is not None

    def test_scaler_fit_transform(self):
        """Test scaler fit and transform."""
        X_train = np.random.rand(100, 6)
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X_train)

        # Check scaled data has mean ~0 and std ~1
        assert np.allclose(X_scaled.mean(), 0, atol=0.1)
        assert np.allclose(X_scaled.std(), 1, atol=0.1)

    def test_scaler_transform(self):
        """Test scaler transform on new data."""
        X_train = np.random.rand(100, 6)
        X_test = np.random.rand(20, 6)

        scaler = StandardScaler()
        scaler.fit(X_train)
        X_test_scaled = scaler.transform(X_test)

        assert X_test_scaled.shape == X_test.shape


class TestInference:
    """Test inference service."""

    def test_prediction_endpoint_format(self):
        """Test prediction endpoint returns correct format."""
        from models.predict import app

        with app.test_client() as client:
            # Note: This requires model to be loaded, skip if unavailable
            response = client.post('/predict', json={
                'tenure': 12,
                'monthly_charges': 65.0,
                'total_charges': 780.0,
                'contract_length': 1,
                'internet_service': 1,
                'monthly_services': 4
            })

            # Skip if model not loaded
            if response.status_code == 503:
                pytest.skip("Model not loaded")

            assert response.status_code == 200
            data = response.get_json()
            assert 'prediction' in data
            assert 'churn_probability' in data

    def test_health_check(self):
        """Test health check endpoint."""
        from models.predict import app

        with app.test_client() as client:
            response = client.get('/health')

            # May be 503 if model not loaded, still valid response
            assert response.status_code in [200, 503]


class TestMetrics:
    """Test metric calculations."""

    def test_accuracy_calculation(self):
        """Test accuracy metric."""
        from sklearn.metrics import accuracy_score

        y_true = [0, 1, 1, 0, 1]
        y_pred = [0, 1, 0, 0, 1]

        acc = accuracy_score(y_true, y_pred)
        assert acc == 0.8

    def test_precision_calculation(self):
        """Test precision metric."""
        from sklearn.metrics import precision_score

        y_true = [0, 1, 1, 0, 1]
        y_pred = [0, 1, 0, 0, 1]

        prec = precision_score(y_true, y_pred)
        assert prec == 1.0

    def test_recall_calculation(self):
        """Test recall metric."""
        from sklearn.metrics import recall_score

        y_true = [0, 1, 1, 0, 1]
        y_pred = [0, 1, 0, 0, 1]

        recall = recall_score(y_true, y_pred)
        assert recall == 2/3


# Fixtures for common test data
@pytest.fixture
def sample_data():
    """Provide sample training data."""
    X = np.random.rand(100, 6)
    y = np.random.randint(0, 2, 100)
    return X, y


@pytest.fixture
def trained_model(sample_data):
    """Provide a trained model."""
    X, y = sample_data
    model = RandomForestClassifier(n_estimators=10, random_state=42)
    model.fit(X, y)
    return model


@pytest.fixture
def scaler(sample_data):
    """Provide a fitted scaler."""
    X, _ = sample_data
    scaler = StandardScaler()
    scaler.fit(X)
    return scaler


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
